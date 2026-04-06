# GPU Driver Updates — Known Issues

## Post-Update Checklist
1. Verify DCGM exporter is reporting metrics for all GPUs
2. Check NCCL performance with a short training benchmark
3. Confirm vLLM inference latency has not regressed
4. Verify GPU operator pods restarted cleanly
5. Check for new XID errors in dmesg

## Common Issues After Driver Updates

### NCCL Performance Regression
- **Symptom**: Training throughput drops 10-30% after driver update
- **Cause**: NCCL version incompatibility with new driver
- **Fix**: Update NCCL to match driver version, rebuild containers
- **Detection**: `DCGM_FI_PROF_NVLINK_TX_BYTES` drops significantly

### GPU Not Detected After Update
- **Symptom**: `nvidia-smi` shows fewer GPUs than expected
- **Cause**: Driver module failed to load for some GPUs
- **Fix**: Check `dmesg | grep nvidia`, reboot node if needed
- **Detection**: `DCGM_FI_DEV_COUNT` lower than expected

### CUDA Compatibility
- **Symptom**: Workloads crash with CUDA version mismatch errors
- **Cause**: Container CUDA toolkit version incompatible with host driver
- **Fix**: Use nvidia-container-toolkit forward compatibility or update containers
- **Detection**: Pod CrashLoopBackOff with "CUDA driver version is insufficient"
