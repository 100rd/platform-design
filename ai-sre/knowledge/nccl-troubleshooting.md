# NCCL Troubleshooting Guide

## Common NCCL Failures

### NCCL Timeout
- **Symptom**: Training hangs, then fails with "NCCL timeout" after 30-60 min
- **Cause**: Network issue between GPU nodes (often EFA or NVLink)
- **Investigation**:
  1. Check `DCGM_FI_PROF_NVLINK_TX_BYTES` for NVLink health
  2. Check EFA device counters: `fi_info -p efa`
  3. Look for packet drops on Cilium: `cilium_drop_count_total`
  4. Check if any participating node has high CPU steal time
- **Fix**: Restart the training job; if persistent, check EFA adapter health

### NCCL Init Failed
- **Symptom**: "NCCL WARN Failed to initialize" on job start
- **Cause**: IPC (shared memory) limits too low, or GPU topology misconfigured
- **Investigation**:
  1. Check `/dev/shm` size: should be at least 1GB per GPU
  2. Verify `nvidia-smi topo -m` shows expected NVLink/NVSwitch topology
  3. Check NCCL debug logs: set `NCCL_DEBUG=INFO`
- **Fix**: Increase shm-size in pod spec, or fix GPU topology

### NCCL AllReduce Slow
- **Symptom**: AllReduce bandwidth well below theoretical maximum
- **Cause**: Suboptimal NCCL algorithm or tree configuration
- **Investigation**:
  1. Check `NCCL_ALGO` and `NCCL_PROTO` settings
  2. Measure actual bandwidth with `nccl-tests` suite
  3. Compare with baseline: H100 NVLink should get ~450 GB/s
- **Fix**: Tune NCCL environment variables, ensure NVSwitch is active
