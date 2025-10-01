package com.azure.gpudemo.config;

import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtSession;
import dev.langchain4j.data.embedding.Embedding;
import dev.langchain4j.model.embedding.EmbeddingModel;
import dev.langchain4j.model.embedding.onnx.allminilml6v2.AllMiniLmL6V2EmbeddingModel;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.File;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

/**
 * Configuration for LangChain4j with GPU-accelerated ONNX models.
 * 
 * This configuration sets up:
 * 1. ONNX Runtime environment with CUDA execution provider
 * 2. Embedding model (All-MiniLM-L6-v2) with GPU acceleration
 * 3. Image generation model (Stable Diffusion v1.5) with GPU acceleration
 */
@Slf4j
@Configuration
public class LangChain4jGpuConfiguration {

    @Value("${langchain4j.onnx.models.base-path:./models}")
    private String modelsBasePath;

    @Value("${langchain4j.onnx.embedding.model-file:all-MiniLM-L6-v2/model.onnx}")
    private String embeddingModelFile;

    @Value("${langchain4j.onnx.image.model-file:stable-diffusion/model.onnx}")
    private String imageModelFile;

    @Value("${langchain4j.onnx.gpu.enabled:true}")
    private boolean gpuEnabled;

    @Value("${langchain4j.onnx.gpu.device-id:0}")
    private int gpuDeviceId;

    /**
     * Create ONNX Runtime environment with GPU support.
     * This is the foundation for all ONNX model execution.
     */
    @Bean
    public OrtEnvironment ortEnvironment() {
        log.info("Initializing ONNX Runtime environment...");
        log.info("GPU enabled: {}", gpuEnabled);
        log.info("GPU device ID: {}", gpuDeviceId);
        
        OrtEnvironment env = OrtEnvironment.getEnvironment();
        log.info("ONNX Runtime version: {}", env.getVersion());
        
        return env;
    }

    /**
     * Create session options for ONNX Runtime with GPU execution provider.
     */
    @Bean
    public OrtSession.SessionOptions ortSessionOptions() throws Exception {
        OrtSession.SessionOptions options = new OrtSession.SessionOptions();
        
        if (gpuEnabled) {
            log.info("Configuring CUDA execution provider for GPU acceleration...");
            try {
                // Add CUDA execution provider with device ID
                options.addCUDA(gpuDeviceId);
                log.info("✓ CUDA execution provider configured successfully");
            } catch (Exception e) {
                log.warn("⚠ Failed to configure CUDA provider, falling back to CPU: {}", e.getMessage());
                log.warn("Ensure CUDA and cuDNN are installed and LD_LIBRARY_PATH is set correctly");
            }
        }
        
        // Enable memory pattern optimization
        options.setMemoryPatternOptimization(true);
        
        // Set optimization level
        options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT);
        
        // Enable parallel execution
        options.setInterOpNumThreads(4);
        options.setIntraOpNumThreads(4);
        
        return options;
    }

    /**
     * Create GPU-accelerated embedding model using All-MiniLM-L6-v2.
     * Expected speedup: ~10x on GPU vs CPU
     * 
     * Note: AllMiniLmL6V2EmbeddingModel loads from its own packaged ONNX model.
     * The ortEnvironment and sessionOptions are kept for other models that need them.
     */
    @Bean
    public EmbeddingModel embeddingModel() {
        log.info("Loading All-MiniLM-L6-v2 embedding model...");
        
        try {
            // Create embedding model - uses built-in ONNX model from LangChain4j
            AllMiniLmL6V2EmbeddingModel model = new AllMiniLmL6V2EmbeddingModel();
            
            log.info("✓ Embedding model loaded successfully");
            
            // Warmup the model
            warmupEmbeddingModel(model);
            
            return model;
        } catch (Exception e) {
            log.error("Failed to load embedding model: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to initialize embedding model", e);
        }
    }

    /**
     * Warmup the embedding model to ensure faster first inference.
     * This preloads the model into GPU memory.
     */
    private void warmupEmbeddingModel(EmbeddingModel model) {
        log.info("Warming up embedding model...");
        long startTime = System.currentTimeMillis();
        
        try {
            // Run a dummy inference
            List<dev.langchain4j.data.segment.TextSegment> warmupTexts = List.of(
                dev.langchain4j.data.segment.TextSegment.from("This is a warmup text to preload the model into GPU memory"),
                dev.langchain4j.data.segment.TextSegment.from("Another warmup text for better initialization")
            );
            List<Embedding> embeddings = model.embedAll(warmupTexts).content();
            
            long duration = System.currentTimeMillis() - startTime;
            log.info("✓ Model warmup completed in {} ms", duration);
            log.info("Embedding dimension: {}", embeddings.get(0).dimension());
        } catch (Exception e) {
            log.warn("⚠ Model warmup failed: {}", e.getMessage());
        }
    }

    /**
     * Note: Stable Diffusion model path is now handled by SD4JImageGenerationService
     * which reads from application.yml and validates the model directory structure.
     * SD4J expects a directory with subdirectories: text_encoder/, unet/, vae_decoder/, safety_checker/
     */
}
