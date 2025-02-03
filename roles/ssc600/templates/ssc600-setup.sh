#!/bin/bash
set -x

# Try to move ALL kernel threads to the non-rt cores
pgrep -P 2 | xargs -i sudo taskset -p $NON_RT_CORES {}
# Assign CPU mask for all workqueues.
find /sys/devices/virtual/workqueue -name cpumask  -exec sh -c "echo $NON_RT_CORES > {}" ';'
# Disable transparent hugepages, can cause page faults
echo never > /sys/kernel/mm/transparent_hugepage/enabled
# kernel memory merging, can cause page faults
echo 0 > /sys/kernel/mm/ksm/run
# and timer migrations
echo 0 > /proc/sys/kernel/timer_migration
# Lengthen the virtual memory update interval, only relevant for older kernels
echo 60 > /proc/sys/vm/stat_interval
# Set the scaling governor to *performance*
echo "performance" | sudo tee -a /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Make sure turbo boost is disabled
echo 1 | sudo tee -a /sys/devices/system/cpu/intel_pstate/no_turbo

set -e

# L3 partitioning
echo "Partitioning the cache"
pqos -e "llc:0=$NON_RT_CACHE;llc:1=$RT_CACHE"
pqos -a "llc:1=$RT_CORES"

# Process bus / networking
echo "Configuring network card interrupts and threads"
for nic in $NICS
do
	IRQS=$(grep $nic /proc/interrupts | cut -d':' -f1)
	for irq in $IRQS
	do
	 echo $CPUMASK | sudo tee /proc/irq/$irq/smp_affinity
	 tasks=$(ps axo pid,command | grep -e "irq/$irq-" | grep -v grep | awk '{print $1}')
	 for pid in $tasks
	 do
	   sudo taskset -p "0x$CPUMASK" $pid
	 done
	done
done