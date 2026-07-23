// SPDX-License-Identifier: GPL-2.0
/*
 * Minimal host-side validator for the Catapult v3 Arria 10 chained-DMA
 * endpoint. This is intentionally a test driver, not a production DMA API.
 */

#include <linux/bitops.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/dma-mapping.h>
#include <linux/io.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/slab.h>

#define CAT_VENDOR_ID			0x1172
#define CAT_DEVICE_ID			0xe004

#define CAT_BAR_DMA			0
#define CAT_BAR_APP			4
#define CAT_BAR_DMA_MAP_SIZE		0x1000
#define CAT_BAR_APP_MAP_SIZE		0x101000

#define CAT_APP_DESIGN_ID		0x100000
#define CAT_APP_ABI_VERSION		0x100004
#define CAT_APP_HEARTBEAT		0x100008
#define CAT_APP_CAPABILITIES		0x10000c
#define CAT_APP_RESET_COUNT		0x100010
#define CAT_APP_ERROR_COUNT		0x100014
#define CAT_APP_SCRATCH			0x100018

#define CAT_EXPECTED_DESIGN_ID		0x43444d41
#define CAT_EXPECTED_ABI_MAJOR		1

#define CAT_WR_REG_BASE			0x00
#define CAT_RD_REG_BASE			0x10
#define CAT_REG_HEADER			0x00
#define CAT_REG_TABLE_HI		0x04
#define CAT_REG_TABLE_LO		0x08
#define CAT_REG_LAST_PTR		0x0c

#define CAT_HEADER_EPLAST		BIT(18)
#define CAT_HEADER_DESC_COUNT		1
#define CAT_EPLAST_PENDING		0xffffffff
#define CAT_EPLAST_MASK			0x0000ffff

/*
 * Length shares DW0 with MSI/EPLAST bits at 16/17. Keep it below 2^16
 * DWORDs so milestone 1 can use a single unambiguous descriptor.
 */
#define CAT_DMA_MAX_BYTES		(0xffffU * sizeof(u32))
#define CAT_DMA_DEFAULT_BYTES		(128U * 1024U)
#define CAT_DMA_DEFAULT_LOOPS		1U
#define CAT_DMA_MAX_LOOPS		100000U
#define CAT_DMA_TIMEOUT_MS		1000U

struct cat_dma_desc {
	__le32 control_length;
	__le32 endpoint_addr;
	__le32 host_addr_hi;
	__le32 host_addr_lo;
} __packed;

struct cat_dma_table {
	__le32 header[4];
	struct cat_dma_desc desc;
} __packed;

struct cat_dma_dev {
	struct pci_dev *pdev;
	void __iomem *bar_dma;
	void __iomem *bar_app;
	struct mutex test_lock;
	char result[512];
};

struct cat_dma_buffers {
	void *source;
	dma_addr_t source_dma;
	void *destination;
	dma_addr_t destination_dma;
	struct cat_dma_table *read_table;
	dma_addr_t read_table_dma;
	struct cat_dma_table *write_table;
	dma_addr_t write_table_dma;
	size_t bytes;
};

static inline void __iomem *cat_dma_reg(struct cat_dma_dev *cat, u32 offset)
{
	return (u8 __iomem *)cat->bar_dma + offset;
}

static inline void __iomem *cat_app_reg(struct cat_dma_dev *cat, u32 offset)
{
	return (u8 __iomem *)cat->bar_app + offset;
}

static void cat_fill_pattern(void *buffer, size_t bytes, u32 loop)
{
	u8 *data = buffer;
	size_t i;

	for (i = 0; i < bytes; ++i)
		data[i] = (u8)((i * 131U) ^ (i >> 8) ^ (loop * 17U));
}

static void cat_prepare_table(struct cat_dma_table *table,
			      dma_addr_t table_dma, dma_addr_t payload_dma,
			      size_t bytes)
{
	u32 dwords = bytes / sizeof(u32);

	memset(table, 0, sizeof(*table));
	table->header[0] = cpu_to_le32(CAT_HEADER_DESC_COUNT |
					      CAT_HEADER_EPLAST);
	table->header[1] = cpu_to_le32(upper_32_bits(table_dma));
	table->header[2] = cpu_to_le32(lower_32_bits(table_dma));
	table->header[3] = cpu_to_le32(CAT_EPLAST_PENDING);

	table->desc.control_length = cpu_to_le32(dwords);
	table->desc.endpoint_addr = cpu_to_le32(0);
	table->desc.host_addr_hi = cpu_to_le32(upper_32_bits(payload_dma));
	table->desc.host_addr_lo = cpu_to_le32(lower_32_bits(payload_dma));
}

static int cat_wait_eplast(struct cat_dma_table *table)
{
	unsigned long deadline = jiffies + msecs_to_jiffies(CAT_DMA_TIMEOUT_MS);
	u32 eplast;

	do {
		dma_rmb();
		eplast = le32_to_cpu(READ_ONCE(table->header[3]));
		if ((eplast & CAT_EPLAST_MASK) == 0)
			return 0;
		usleep_range(50, 100);
	} while (time_before(jiffies, deadline));

	return -ETIMEDOUT;
}

static int cat_submit(struct cat_dma_dev *cat, u32 register_base,
		      struct cat_dma_table *table, dma_addr_t table_dma)
{
	u32 header = le32_to_cpu(table->header[0]);

	dma_wmb();
	iowrite32(header, cat_dma_reg(cat, register_base + CAT_REG_HEADER));
	iowrite32(upper_32_bits(table_dma),
		  cat_dma_reg(cat, register_base + CAT_REG_TABLE_HI));
	iowrite32(lower_32_bits(table_dma),
		  cat_dma_reg(cat, register_base + CAT_REG_TABLE_LO));

	/* Descriptor index zero is ready; this write starts the engine. */
	iowrite32(0, cat_dma_reg(cat, register_base + CAT_REG_LAST_PTR));

	return cat_wait_eplast(table);
}

static void cat_free_buffers(struct cat_dma_dev *cat,
			     struct cat_dma_buffers *buffers)
{
	struct device *dev = &cat->pdev->dev;

	if (buffers->write_table)
		dma_free_coherent(dev, sizeof(*buffers->write_table),
				  buffers->write_table,
				  buffers->write_table_dma);
	if (buffers->read_table)
		dma_free_coherent(dev, sizeof(*buffers->read_table),
				  buffers->read_table,
				  buffers->read_table_dma);
	if (buffers->destination)
		dma_free_coherent(dev, buffers->bytes, buffers->destination,
				  buffers->destination_dma);
	if (buffers->source)
		dma_free_coherent(dev, buffers->bytes, buffers->source,
				  buffers->source_dma);
}

static int cat_alloc_buffers(struct cat_dma_dev *cat,
			     struct cat_dma_buffers *buffers, size_t bytes)
{
	struct device *dev = &cat->pdev->dev;

	memset(buffers, 0, sizeof(*buffers));
	buffers->bytes = bytes;

	buffers->source = dma_alloc_coherent(dev, bytes, &buffers->source_dma,
					     GFP_KERNEL);
	if (!buffers->source)
		goto no_memory;

	buffers->destination =
		dma_alloc_coherent(dev, bytes, &buffers->destination_dma,
				   GFP_KERNEL);
	if (!buffers->destination)
		goto no_memory;

	buffers->read_table =
		dma_alloc_coherent(dev, sizeof(*buffers->read_table),
				   &buffers->read_table_dma, GFP_KERNEL);
	if (!buffers->read_table)
		goto no_memory;

	buffers->write_table =
		dma_alloc_coherent(dev, sizeof(*buffers->write_table),
				   &buffers->write_table_dma, GFP_KERNEL);
	if (!buffers->write_table)
		goto no_memory;

	return 0;

no_memory:
	cat_free_buffers(cat, buffers);
	return -ENOMEM;
}

static int cat_run_test(struct cat_dma_dev *cat, u32 bytes, u32 loops)
{
	struct cat_dma_buffers buffers;
	u64 read_ns = 0;
	u64 write_ns = 0;
	u64 total_bytes;
	u64 read_mbps;
	u64 write_mbps;
	ktime_t start;
	u32 loop;
	int ret;

	ret = cat_alloc_buffers(cat, &buffers, bytes);
	if (ret)
		return ret;

	for (loop = 0; loop < loops; ++loop) {
		cat_fill_pattern(buffers.source, bytes, loop);
		memset(buffers.destination, 0xa5, bytes);

		cat_prepare_table(buffers.read_table, buffers.read_table_dma,
				  buffers.source_dma, bytes);
		start = ktime_get();
		ret = cat_submit(cat, CAT_RD_REG_BASE, buffers.read_table,
				 buffers.read_table_dma);
		read_ns += ktime_to_ns(ktime_sub(ktime_get(), start));
		if (ret) {
			scnprintf(cat->result, sizeof(cat->result),
				  "FAIL direction=host-to-fpga loop=%u error=%d\n",
				  loop, ret);
			goto out;
		}

		cat_prepare_table(buffers.write_table, buffers.write_table_dma,
				  buffers.destination_dma, bytes);
		start = ktime_get();
		ret = cat_submit(cat, CAT_WR_REG_BASE, buffers.write_table,
				 buffers.write_table_dma);
		write_ns += ktime_to_ns(ktime_sub(ktime_get(), start));
		if (ret) {
			scnprintf(cat->result, sizeof(cat->result),
				  "FAIL direction=fpga-to-host loop=%u error=%d\n",
				  loop, ret);
			goto out;
		}

		dma_rmb();
		if (memcmp(buffers.source, buffers.destination, bytes)) {
			u8 *source = buffers.source;
			u8 *destination = buffers.destination;
			u32 mismatch;

			for (mismatch = 0; mismatch < bytes; ++mismatch)
				if (source[mismatch] != destination[mismatch])
					break;

			scnprintf(cat->result, sizeof(cat->result),
				  "FAIL compare loop=%u offset=%u expected=0x%02x actual=0x%02x\n",
				  loop, mismatch, source[mismatch],
				  destination[mismatch]);
			ret = -EIO;
			goto out;
		}
	}

	total_bytes = (u64)bytes * loops;
	read_mbps = read_ns ? div64_u64(total_bytes * 1000, read_ns) : 0;
	write_mbps = write_ns ? div64_u64(total_bytes * 1000, write_ns) : 0;
	scnprintf(cat->result, sizeof(cat->result),
		  "PASS bytes=%u loops=%u host_to_fpga_MBps=%llu fpga_to_host_MBps=%llu total_errors=0\n",
		  bytes, loops, read_mbps, write_mbps);
	ret = 0;

out:
	cat_free_buffers(cat, &buffers);
	return ret;
}

static ssize_t info_show(struct device *dev, struct device_attribute *attr,
			 char *buf)
{
	struct cat_dma_dev *cat = pci_get_drvdata(to_pci_dev(dev));

	return sysfs_emit(buf,
			  "design_id=0x%08x\n"
			  "abi_version=0x%08x\n"
			  "heartbeat=0x%08x\n"
			  "capabilities=0x%08x\n"
			  "reset_count=%u\n"
			  "error_count=%u\n"
			  "scratch=0x%08x\n"
			  "bar0_bytes=%llu\n"
			  "bar4_bytes=%llu\n",
			  ioread32(cat_app_reg(cat, CAT_APP_DESIGN_ID)),
			  ioread32(cat_app_reg(cat, CAT_APP_ABI_VERSION)),
			  ioread32(cat_app_reg(cat, CAT_APP_HEARTBEAT)),
			  ioread32(cat_app_reg(cat, CAT_APP_CAPABILITIES)),
			  ioread32(cat_app_reg(cat, CAT_APP_RESET_COUNT)),
			  ioread32(cat_app_reg(cat, CAT_APP_ERROR_COUNT)),
			  ioread32(cat_app_reg(cat, CAT_APP_SCRATCH)),
			  (unsigned long long)
			  pci_resource_len(cat->pdev, CAT_BAR_DMA),
			  (unsigned long long)
			  pci_resource_len(cat->pdev, CAT_BAR_APP));
}

static ssize_t result_show(struct device *dev, struct device_attribute *attr,
			   char *buf)
{
	struct cat_dma_dev *cat = pci_get_drvdata(to_pci_dev(dev));
	ssize_t length;

	mutex_lock(&cat->test_lock);
	length = sysfs_emit(buf, "%s", cat->result);
	mutex_unlock(&cat->test_lock);

	return length;
}

static ssize_t run_store(struct device *dev, struct device_attribute *attr,
			 const char *buf, size_t count)
{
	struct cat_dma_dev *cat = pci_get_drvdata(to_pci_dev(dev));
	u32 bytes = CAT_DMA_DEFAULT_BYTES;
	u32 loops = CAT_DMA_DEFAULT_LOOPS;
	int fields;
	int ret;

	fields = sscanf(buf, "%u %u", &bytes, &loops);
	if (fields < 1)
		return -EINVAL;
	if (bytes < sizeof(u32) || bytes > CAT_DMA_MAX_BYTES ||
	    !IS_ALIGNED(bytes, sizeof(u32)))
		return -EINVAL;
	if (!loops || loops > CAT_DMA_MAX_LOOPS)
		return -EINVAL;

	if (mutex_lock_interruptible(&cat->test_lock))
		return -ERESTARTSYS;
	ret = cat_run_test(cat, bytes, loops);
	mutex_unlock(&cat->test_lock);

	return ret ? ret : count;
}

static DEVICE_ATTR_RO(info);
static DEVICE_ATTR_RO(result);
static DEVICE_ATTR_WO(run);

static struct attribute *cat_dma_attrs[] = {
	&dev_attr_info.attr,
	&dev_attr_result.attr,
	&dev_attr_run.attr,
	NULL,
};

static const struct attribute_group cat_dma_attr_group = {
	.name = "catapult_dma",
	.attrs = cat_dma_attrs,
};

static int cat_dma_probe(struct pci_dev *pdev,
			 const struct pci_device_id *pci_id)
{
	struct cat_dma_dev *cat;
	u32 design_id;
	u32 abi_version;
	int ret;

	ret = pci_enable_device_mem(pdev);
	if (ret)
		return ret;

	ret = pci_request_regions(pdev, "catapult_dma");
	if (ret)
		goto disable_device;

	if (pci_resource_len(pdev, CAT_BAR_DMA) < CAT_BAR_DMA_MAP_SIZE ||
	    pci_resource_len(pdev, CAT_BAR_APP) < CAT_BAR_APP_MAP_SIZE) {
		dev_err(&pdev->dev,
			"BAR aperture too small: BAR0=%llu BAR4=%llu\n",
			(unsigned long long)pci_resource_len(pdev, CAT_BAR_DMA),
			(unsigned long long)pci_resource_len(pdev, CAT_BAR_APP));
		ret = -ENODEV;
		goto release_regions;
	}

	ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
	if (ret) {
		ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
		if (ret)
			goto release_regions;
	}

	pci_set_master(pdev);

	cat = devm_kzalloc(&pdev->dev, sizeof(*cat), GFP_KERNEL);
	if (!cat) {
		ret = -ENOMEM;
		goto clear_master;
	}

	cat->pdev = pdev;
	mutex_init(&cat->test_lock);
	strscpy(cat->result, "NOT_RUN\n", sizeof(cat->result));

	cat->bar_dma = pci_iomap_range(pdev, CAT_BAR_DMA, 0,
				       CAT_BAR_DMA_MAP_SIZE);
	if (!cat->bar_dma) {
		ret = -ENOMEM;
		goto clear_master;
	}

	cat->bar_app = pci_iomap_range(pdev, CAT_BAR_APP, 0,
				       CAT_BAR_APP_MAP_SIZE);
	if (!cat->bar_app) {
		ret = -ENOMEM;
		goto unmap_dma;
	}

	pci_set_drvdata(pdev, cat);

	design_id = ioread32(cat_app_reg(cat, CAT_APP_DESIGN_ID));
	abi_version = ioread32(cat_app_reg(cat, CAT_APP_ABI_VERSION));
	if (design_id != CAT_EXPECTED_DESIGN_ID ||
	    (abi_version >> 16) != CAT_EXPECTED_ABI_MAJOR) {
		dev_err(&pdev->dev,
			"ABI mismatch: design_id=0x%08x abi=0x%08x\n",
			design_id, abi_version);
		ret = -ENODEV;
		goto unmap_app;
	}

	ret = sysfs_create_group(&pdev->dev.kobj, &cat_dma_attr_group);
	if (ret)
		goto unmap_app;

	dev_info(&pdev->dev,
		 "Catapult DMA validator ready, BAR0=%llu bytes BAR4=%llu bytes\n",
		 (unsigned long long)pci_resource_len(pdev, CAT_BAR_DMA),
		 (unsigned long long)pci_resource_len(pdev, CAT_BAR_APP));
	return 0;

unmap_app:
	pci_iounmap(pdev, cat->bar_app);
unmap_dma:
	pci_iounmap(pdev, cat->bar_dma);
clear_master:
	pci_clear_master(pdev);
release_regions:
	pci_release_regions(pdev);
disable_device:
	pci_disable_device(pdev);
	return ret;
}

static void cat_dma_remove(struct pci_dev *pdev)
{
	struct cat_dma_dev *cat = pci_get_drvdata(pdev);

	sysfs_remove_group(&pdev->dev.kobj, &cat_dma_attr_group);
	pci_iounmap(pdev, cat->bar_app);
	pci_iounmap(pdev, cat->bar_dma);
	pci_clear_master(pdev);
	pci_release_regions(pdev);
	pci_disable_device(pdev);
}

static const struct pci_device_id cat_dma_pci_ids[] = {
	{ PCI_DEVICE(CAT_VENDOR_ID, CAT_DEVICE_ID) },
	{ }
};
MODULE_DEVICE_TABLE(pci, cat_dma_pci_ids);

static struct pci_driver cat_dma_driver = {
	.name = "catapult_dma",
	.id_table = cat_dma_pci_ids,
	.probe = cat_dma_probe,
	.remove = cat_dma_remove,
};
module_pci_driver(cat_dma_driver);

MODULE_AUTHOR("Project-Conterweight contributors");
MODULE_DESCRIPTION("Catapult v3 Arria 10 PCIe DMA validation driver");
MODULE_LICENSE("GPL");
