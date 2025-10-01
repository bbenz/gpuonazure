# Docker Build Quick Reference

## Current Issue: GLIBC 2.38 Compatibility

**Problem**: `libortextensions.so` requires GLIBC 2.38+, but Ubuntu 22.04 (our CUDA 11.8 base) has GLIBC 2.35.

**Solution**: Build `libortextensions.so` from source for Ubuntu 22.04.

## Build Command

```bash
cd /mnt/c/githublocal/gpuonazure
docker build -f Dockerfile.slim -t gpu-langchain4j-demo:glibc-fix . 2>&1 | tee docker-build-v2.log
```

## Build Stages & Timeline

### Stage 1: Java Application Build (~30 seconds)
```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build
- Download Maven dependencies (cached)
- Compile Java source code
- Package as JAR (~120MB)
```

### Stage 1.5: libortextensions.so Build (~5-8 minutes)
```dockerfile
FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04 AS ortextensions-builder
```

**Steps:**
1. Install build tools (git, gcc, python3)
2. **Install CMake 3.27+ from Kitware** (fixes version requirement) - ~30s
3. Clone onnxruntime-extensions v0.11.0 - ~20s
4. CMake configure with `-DOCOS_BUILD_PYTHON=OFF` - ~10s
5. Build C++ library with `cmake --build` - ~5-6 minutes
6. Output: `/build/onnxruntime-extensions/build/lib/libortextensions.so`

**Key Fixes Applied:**
- ✅ Install CMake 3.27+ (was 3.22, required 3.25+)
- ✅ Use direct CMake (not build.sh which had parameter issues)
- ✅ Disable Python bindings (only need C++ library)

### Stage 2: Runtime Image (~30 seconds)
```dockerfile
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04
- Install Java 21 runtime
- Copy app.jar from stage 1
- Copy libortextensions.so from stage 1.5 ✅
- Copy text_tokenizer files
- Final image: ~1.8GB
```

## Monitoring Build Progress

### Check if still building:
```bash
docker ps -a | grep ortextensions-builder
```

### Watch build log:
```bash
tail -f docker-build-v2.log
```

### Check for completion:
```bash
docker images | grep gpu-langchain4j-demo
```

## Expected Build Output

### Success Messages:
```
#21 [ortextensions-builder 3/7] RUN wget -O - https://apt.kitware.com/...
#21 DONE 2.5s

#22 [ortextensions-builder 4/7] RUN pip3 install numpy
#22 DONE 15.3s

#23 [ortextensions-builder 5/7] RUN git clone --recursive...
#23 DONE 22.1s

#24 [ortextensions-builder 6/7] RUN mkdir -p build && cd build...
#24 127.3 [ 98%] Building CXX object CMakeFiles/ortextensions.dir/...
#24 301.5 [100%] Linking CXX shared library lib/libortextensions.so
#24 DONE 305.2s

#25 [stage-2 7/8] COPY --from=ortextensions-builder...
#25 DONE 0.3s

Successfully built
Successfully tagged gpu-langchain4j-demo:glibc-fix
```

### Common Errors & Fixes:

#### ❌ CMake version too old (3.22 < 3.25)
```
CMake Error: CMake 3.25 or higher is required
```
**Fix**: Install CMake from Kitware repo ✅ (already applied)

#### ❌ build.sh parameter error
```
CMake Error: Unknown argument --skip_tests
```
**Fix**: Use direct CMake instead of build.sh ✅ (already applied)

#### ❌ Missing dependencies
```
fatal: unable to access 'https://github.com/...'
```
**Fix**: Install git, wget, ca-certificates (already in Dockerfile)

## After Build Completes

### 1. Verify Image Created
```bash
docker images | grep glibc-fix
# Expected: gpu-langchain4j-demo:glibc-fix  ~1.8GB
```

### 2. Run Test Suite
```bash
./test-gpu-build.sh
```

**Checks performed:**
- ✅ Image exists
- ✅ Container starts
- ✅ GLIBC compatibility (ldd libortextensions.so)
- ✅ ONNX Runtime providers include CUDA
- ✅ SD4J initializes with CUDA (not CPU fallback)
- ✅ GPU accessible (nvidia-smi)

### 3. Test Image Generation
```bash
./test-gpu-generation.sh
```

**Tests performed:**
- Generate 3 test images with different prompts
- Monitor GPU utilization during generation
- Measure generation time (expect 15-60s with GPU)
- Analyze performance metrics

## Troubleshooting

### Build hangs at "Cloning into 'onnxruntime-extensions'"
- Network issue, wait or restart build

### Build fails at CMake configure
- Check CMake version: `docker run --rm <image> cmake --version`
- Should be 3.27+ (not 3.22)

### Build fails at compile
- Check build log: `grep -i error docker-build-v2.log`
- May need more disk space (build uses ~5GB temporarily)

### libortextensions.so not found in final image
- Check COPY path: should be `/build/onnxruntime-extensions/build/lib/libortextensions.so`
- Verify build stage name: `ortextensions-builder`

## Performance Expectations

| Metric | CPU Mode | GPU Mode (Target) |
|--------|----------|-------------------|
| Image generation time | 180-240s | 15-60s |
| GPU utilization | 0% | 90-100% |
| Startup time | ~30s | ~40s (GPU init) |
| Memory usage | 4GB | 8GB |

## Next Steps After Successful Build

1. ✅ Verify GLIBC compatibility
2. ✅ Test GPU initialization
3. ✅ Generate test images
4. 📊 Analyze performance metrics
5. 🚀 Deploy to Azure Container Apps with GPU profile

---

**Last Updated**: September 30, 2025  
**Build Configuration**: Ubuntu 22.04 + CUDA 11.8 + cuDNN 8 + GLIBC 2.35  
**CMake Version**: 3.27+ (from Kitware)  
**ONNX Runtime Extensions**: v0.11.0 (built from source)
