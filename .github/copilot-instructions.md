# GitHub Copilot Instructions

## Project Overview

This is a **GPU-accelerated AI inference application** built with **Java 21**, **Spring Boot 3.2.5**, **LangChain4j 0.34.0**, and **ONNX Runtime 1.16.3** with **CUDA 12.2** support. The application generates cartoon-style images using Stable Diffusion and computes text embeddings using All-MiniLM-L6-v2, deployed to Azure Container Apps with GPU workload profiles.

## Technology Stack

- **Language**: Java 21 LTS (with `--enable-preview` for virtual threads)
- **Framework**: Spring Boot 3.2.5
- **AI Framework**: LangChain4j 0.34.0 with ONNX Runtime integration
- **Inference Engine**: ONNX Runtime 1.16.3 (CPU + GPU/CUDA 12.2)
- **Build Tool**: Maven 3.9+
- **Cloud Platform**: Azure Container Apps with GPU profiles (T4/A100)
- **Models**: Stable Diffusion v1.5 ONNX, All-MiniLM-L6-v2 ONNX
- **Container Base**: nvidia/cuda:12.2.0-runtime-ubuntu22.04

## Project Structure

```
gpuonazure/
├── src/
│   └── main/
│       ├── java/com/azure/gpudemo/
│       │   ├── GpuLangchain4jDemoApplication.java    # Main entry point
│       │   ├── config/
│       │   │   └── LangChain4jGpuConfiguration.java  # GPU beans config
│       │   ├── service/
│       │   │   ├── LangChain4jGpuService.java        # Core inference
│       │   │   └── ModelManagementService.java       # Model downloads
│       │   └── controller/
│       │       └── ClippyController.java             # REST API
│       └── resources/
│           ├── application.yml                        # Configuration
│           └── static/
│               ├── index.html                         # Web UI
│               ├── css/styles.css                     # Custom styles
│               └── js/app.js                          # Frontend logic
├── pom.xml                                            # Maven dependencies
├── Dockerfile                                         # Multi-stage build
├── download-models.sh                                 # Model download script
├── deploy-aca.sh                                      # Azure deployment
└── README.md                                          # Project docs
```

## Coding Standards

### Java Conventions

1. **Java Version**: Always use Java 21 features
   - Virtual threads: `Thread.startVirtualThread(() -> {})`
   - Pattern matching for switch
   - Record patterns
   - Enable preview features: `--enable-preview`

2. **Spring Boot Patterns**:
   - Use `@Configuration` for bean definitions
   - Use `@Service` for business logic
   - Use `@RestController` with `@RequestMapping` for APIs
   - Use `@Value` or `@ConfigurationProperties` for configuration
   - Use constructor injection (not field injection)

3. **Error Handling**:
   - Use `@ControllerAdvice` for global exception handling
   - Return proper HTTP status codes (400, 404, 500)
   - Log errors with context using SLF4J
   - Use custom exceptions for business logic errors

4. **Resource Management**:
   - Use try-with-resources for closeable resources
   - Implement `@PreDestroy` for cleanup in services
   - Close ONNX sessions properly

5. **Null Safety**:
   - Use `Optional<T>` for nullable return values
   - Validate inputs with `@Valid` and `@NotNull`
   - Check preconditions with `Objects.requireNonNull()`

### LangChain4j Integration

1. **Model Configuration**:
   - Define models as Spring beans in `LangChain4jGpuConfiguration`
   - Use `OrtEnvironment` for ONNX Runtime session management
   - Configure GPU device ID and thread pools

2. **Service Layer**:
   - Keep inference logic in `LangChain4jGpuService`
   - Use model management in `ModelManagementService`
   - Implement warmup methods for model loading

3. **ONNX Runtime**:
   - Always specify execution provider: `ExecutionProvider.CUDA`
   - Set device ID: `OrtSession.SessionOptions().setGpuDeviceId(0)`
   - Configure thread pools for optimal performance

### REST API Design

1. **Endpoints**:
   - Use `/api/langchain4j/*` as base path
   - POST `/image` - Generate images from text prompts
   - POST `/embeddings` - Compare text similarity
   - GET `/metrics` - System health and model status
   - GET `/health` - Simple health check
   - Return proper HTTP status codes

2. **Request/Response**:
   - Use DTOs (records) for request/response bodies
   - Validate inputs with Jakarta Bean Validation
   - Return `ResponseEntity<T>` with proper status
   - Use `produces = MediaType.IMAGE_PNG_VALUE` for images

3. **Error Responses**:
   ```java
   {
     "error": "Error message",
     "status": 400,
     "timestamp": "2025-09-29T12:00:00Z"
   }
   ```

### Configuration

1. **application.yml Structure**:
   ```yaml
   spring:
     application:
       name: gpu-langchain4j-demo
   
   gpu:
     langchain4j:
       gpu:
         enabled: true
         device-id: 0
       model:
         dir: ./models
   ```

2. **Externalization**:
   - Use environment variables for secrets
   - Use profiles for environment-specific config
   - Document all configuration properties

### Testing

1. **Unit Tests**:
   - Use JUnit 5
   - Mock external dependencies with Mockito
   - Test error scenarios
   - Target 80%+ code coverage

2. **Integration Tests**:
   - Use `@SpringBootTest` for full context
   - Use `@WebMvcTest` for controller tests
   - Mock ONNX models in tests (too large to include)

### Docker

1. **Multi-stage Builds**:
   - Stage 1: Maven build (eclipse-temurin-21)
   - Stage 2: Runtime (nvidia/cuda:12.2.0-runtime-ubuntu22.04)

2. **Best Practices**:
   - Use layer caching for dependencies
   - Create non-root user for runtime
   - Set proper CUDA environment variables
   - Include health check in Dockerfile

### Azure Deployment

1. **Container Apps**:
   - Use GPU workload profiles (NC8as_T4_v3 or NC24ads_A100_v4)
   - Set appropriate CPU/memory (4 CPU, 16GB RAM minimum)
   - Configure autoscaling (min: 1, max: 3)
   - Enable ingress with external access

2. **Environment Variables**:
   ```bash
   SPRING_PROFILES_ACTIVE=production
   GPU_LANGCHAIN4J_GPU_ENABLED=true
   GPU_LANGCHAIN4J_GPU_DEVICE_ID=0
   JAVA_OPTS=-Xmx8g -XX:+UseZGC
   ```

## Common Patterns

### 1. Adding New Inference Endpoint

```java
@PostMapping("/new-inference")
public ResponseEntity<?> performInference(@Valid @RequestBody RequestDTO request) {
    try {
        var result = gpuService.performInference(request);
        return ResponseEntity.ok(result);
    } catch (Exception e) {
        log.error("Inference failed", e);
        return ResponseEntity.status(500)
            .body(Map.of("error", e.getMessage()));
    }
}
```

### 2. Loading New ONNX Model

```java
@Bean
public OrtSession newModel(OrtEnvironment env) throws OrtException {
    var options = new OrtSession.SessionOptions();
    options.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.PARALLEL);
    options.addCUDA(gpuDeviceId);
    options.setInterOpNumThreads(4);
    options.setIntraOpNumThreads(8);
    
    String modelPath = modelDir + "/new-model/model.onnx";
    return env.createSession(modelPath, options);
}
```

### 3. GPU Resource Management

```java
@PreDestroy
public void cleanup() {
    try {
        if (stableDiffusionSession != null) {
            stableDiffusionSession.close();
        }
        if (ortEnvironment != null) {
            ortEnvironment.close();
        }
    } catch (Exception e) {
        log.error("Error during cleanup", e);
    }
}
```

### 4. Error Handling

```java
@ControllerAdvice
public class GlobalExceptionHandler {
    
    @ExceptionHandler(OrtException.class)
    public ResponseEntity<?> handleOrtException(OrtException e) {
        log.error("ONNX Runtime error", e);
        return ResponseEntity.status(500)
            .body(Map.of("error", "Inference failed: " + e.getMessage()));
    }
}
```

## Performance Optimization

1. **JVM Options**:
   - Use ZGC for low-latency GC: `-XX:+UseZGC -XX:+ZGenerational`
   - Set appropriate heap size: `-Xmx8g`
   - Enable preview features: `--enable-preview`

2. **ONNX Runtime**:
   - Use GPU execution provider
   - Configure thread pools (inter-op: 4, intra-op: 8)
   - Implement model warmup on startup

3. **Spring Boot**:
   - Use virtual threads for async operations
   - Configure graceful shutdown
   - Enable HTTP compression

## Security Considerations

1. **Input Validation**:
   - Validate all user inputs
   - Limit prompt length (max 500 chars)
   - Sanitize file paths

2. **Resource Limits**:
   - Implement rate limiting
   - Set request timeouts
   - Limit concurrent requests

3. **Secrets Management**:
   - Never commit secrets to git
   - Use Azure Key Vault for production
   - Use environment variables

## Debugging Tips

1. **GPU Issues**:
   - Check CUDA availability: `nvidia-smi`
   - Verify ONNX Runtime GPU: Check health endpoint
   - Review GPU memory usage

2. **Model Loading**:
   - Verify model file paths
   - Check file permissions
   - Review model download logs

3. **Performance**:
   - Enable DEBUG logging for ONNX Runtime
   - Monitor JVM heap usage
   - Check thread pool utilization

## Git Workflow

1. **Branch Naming**:
   - `feature/description` for new features
   - `bugfix/description` for bug fixes
   - `docs/description` for documentation

2. **Commit Messages**:
   - Use conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`
   - Include context and reasoning
   - Reference issue numbers

3. **Before Commit**:
   - Run tests: `mvn test`
   - Check formatting: `mvn spotless:check`
   - Build successfully: `mvn clean package`

## Additional Resources

- [LangChain4j Documentation](https://docs.langchain4j.dev/)
- [ONNX Runtime Java API](https://onnxruntime.ai/docs/api/java/api/)
- [Spring Boot Reference](https://docs.spring.io/spring-boot/docs/current/reference/html/)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [CUDA Programming Guide](https://docs.nvidia.com/cuda/)

## Notes for AI Assistants

- **Always** use Java 21 syntax and features
- **Always** check GPU availability before GPU operations
- **Always** implement proper resource cleanup
- **Always** validate user inputs
- **Always** handle ONNX Runtime exceptions
- **Never** commit model files to git (too large)
- **Never** hardcode secrets or credentials
- **Prefer** constructor injection over field injection
- **Prefer** records over classes for DTOs
- **Prefer** async operations with virtual threads

---

**Last Updated**: September 29, 2025  
**Project Version**: 0.0.1-SNAPSHOT
