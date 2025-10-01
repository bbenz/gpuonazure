package com.azure.gpudemo.service;

import com.oracle.labs.mlrg.sd4j.SD4J;
import com.oracle.labs.mlrg.sd4j.Schedulers;
import jakarta.annotation.PreDestroy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;

/**
 * Service for generating images using Oracle's SD4J (Stable Diffusion for Java).
 * 
 * SD4J is a complete implementation of Stable Diffusion inference in Java using ONNX Runtime.
 * It includes:
 * - CLIP text encoder with proper tokenization
 * - U-Net for denoising diffusion
 * - VAE decoder for latent-to-pixel conversion
 * - Multiple scheduling algorithms (LMS, Euler Ancestral)
 * - Optional safety checker
 * 
 * This service wraps the SD4J library and integrates it with Spring Boot.
 */
@Slf4j
@Service
public class SD4JImageGenerationService {

    @Value("${langchain4j.onnx.models.base-path:./models}")
    private String modelsBasePath;
    
    @Value("${langchain4j.onnx.gpu.enabled:false}")
    private boolean gpuEnabled;
    
    @Value("${langchain4j.onnx.gpu.device-id:0}")
    private int gpuDeviceId;

    private SD4J stableDiffusionPipeline;
    private boolean initialized = false;

    /**
     * Initialize the SD4J pipeline lazily (on first use) to avoid startup delays.
     */
    private synchronized void initializePipeline() {
        if (initialized) {
            return;
        }

        // Determine execution provider based on configuration
        SD4J.ExecutionProvider executionProvider = gpuEnabled 
            ? SD4J.ExecutionProvider.CUDA 
            : SD4J.ExecutionProvider.CPU;

        try {
            log.info("Initializing SD4J Stable Diffusion pipeline...");
            log.info("Model path: {}/stable-diffusion", modelsBasePath);
            log.info("GPU enabled: {}", gpuEnabled);
            log.info("GPU device ID: {}", gpuDeviceId);

            // Create SD4J configuration
            SD4J.SD4JConfig config = new SD4J.SD4JConfig(
                modelsBasePath + "/stable-diffusion",  // Model path
                executionProvider,                      // CPU or CUDA
                gpuDeviceId,                           // GPU device ID
                SD4J.ModelType.SD1_5                   // Stable Diffusion v1.5
            );

            // Initialize the pipeline
            stableDiffusionPipeline = SD4J.factory(config);
            initialized = true;

            log.info("✓ SD4J Stable Diffusion pipeline initialized successfully");
            log.info("  - Execution provider: {}", executionProvider);
            log.info("  - Model type: SD v1.5");
            log.info("  - Model path: {}/stable-diffusion", modelsBasePath);

        } catch (Exception e) {
            // If GPU initialization failed, try falling back to CPU
            if (gpuEnabled && executionProvider == SD4J.ExecutionProvider.CUDA) {
                log.warn("⚠ GPU initialization failed, attempting CPU fallback...", e);
                try {
                    SD4J.SD4JConfig cpuConfig = new SD4J.SD4JConfig(
                        modelsBasePath + "/stable-diffusion",
                        SD4J.ExecutionProvider.CPU,
                        0,
                        SD4J.ModelType.SD1_5
                    );
                    stableDiffusionPipeline = SD4J.factory(cpuConfig);
                    initialized = true;
                    log.info("✓ SD4J initialized with CPU fallback");
                    log.info("  - Execution provider: CPU (GPU not available)");
                } catch (Exception cpuException) {
                    log.error("Failed to initialize SD4J even with CPU fallback", cpuException);
                    throw new IllegalStateException("SD4J initialization failed: " + cpuException.getMessage(), cpuException);
                }
            } else {
                log.error("Failed to initialize SD4J pipeline", e);
                throw new IllegalStateException("SD4J initialization failed: " + e.getMessage(), e);
            }
        }
    }

    /**
     * Generate an image using Stable Diffusion.
     * 
     * @param prompt The text prompt describing the desired image
     * @param negativePrompt The negative prompt (what to avoid in the image)
     * @param numInferenceSteps Number of diffusion steps (20-50 typical, more = better quality but slower)
     * @param guidanceScale Classifier-free guidance scale (7.5 typical, higher = more prompt adherence)
     * @param seed Random seed for reproducibility
     * @param width Image width in pixels (512 typical for SD 1.5)
     * @param height Image height in pixels (512 typical for SD 1.5)
     * @return PNG image data as byte array
     * @throws IOException If image encoding fails
     */
    public byte[] generateImage(
            String prompt,
            String negativePrompt,
            int numInferenceSteps,
            float guidanceScale,
            int seed,
            int width,
            int height) throws IOException {
        
        if (!initialized) {
            initializePipeline();
        }

        log.info("Generating image with SD4J:");
        log.info("  Prompt: {}", prompt);
        log.info("  Negative: {}", negativePrompt);
        log.info("  Steps: {}, Guidance: {}, Seed: {}", numInferenceSteps, guidanceScale, seed);
        log.info("  Size: {}x{}", width, height);

        long startTime = System.currentTimeMillis();

        try {
            // Create image size
            SD4J.ImageSize imageSize = new SD4J.ImageSize(height, width);

            // Generate image using SD4J
            // Uses Euler Ancestral scheduler by default (good quality/speed balance)
            List<SD4J.SDImage> images = stableDiffusionPipeline.generateImage(
                numInferenceSteps,
                prompt,
                negativePrompt,
                guidanceScale,
                1,  // batch size = 1
                imageSize,
                seed,
                Schedulers.EULER_ANCESTRAL,
                (step) -> {
                    if (step % 10 == 0) {
                        log.debug("  Diffusion step: {}/{}", step, numInferenceSteps);
                    }
                }
            );

            long duration = System.currentTimeMillis() - startTime;
            log.info("✓ Image generated in {} ms ({} seconds)", duration, duration / 1000.0);

            // Get the first (and only) image from the batch
            SD4J.SDImage sdImage = images.get(0);
            BufferedImage bufferedImage = sdImage.image();

            // Check if image passed safety check
            if (!sdImage.isValid()) {
                log.warn("⚠ Image failed safety check (NSFW content detected)");
                // You can either throw an exception or return a placeholder
                // For now, we'll still return the image with a warning
            }

            // Convert BufferedImage to PNG byte array
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            ImageIO.write(bufferedImage, "PNG", baos);
            byte[] imageData = baos.toByteArray();

            log.info("✓ Image encoded to PNG ({} KB)", imageData.length / 1024);
            return imageData;

        } catch (Exception e) {
            log.error("Failed to generate image with SD4J", e);
            throw new IOException("Image generation failed: " + e.getMessage(), e);
        }
    }

    /**
     * Generate an image with default parameters.
     * Good defaults for cartoon-style images.
     */
    public byte[] generateImage(String prompt) throws IOException {
        return generateImage(
            prompt,
            "",      // No negative prompt
            40,      // 40 inference steps (good quality/speed balance)
            7.5f,    // Standard guidance scale
            42,      // Fixed seed for consistency
            512,     // SD 1.5 native resolution
            512
        );
    }

    /**
     * Check if the SD4J pipeline is initialized and ready.
     */
    public boolean isReady() {
        return initialized && stableDiffusionPipeline != null;
    }

    /**
     * Get model status information.
     */
    public String getStatus() {
        if (!initialized) {
            return "Not initialized";
        }
        return String.format("Ready (GPU: %s, Model: SD v1.5)", gpuEnabled ? "enabled" : "disabled");
    }

    /**
     * Clean up resources when the service is destroyed.
     */
    @PreDestroy
    public void cleanup() {
        if (stableDiffusionPipeline != null) {
            try {
                log.info("Closing SD4J pipeline...");
                stableDiffusionPipeline.close();
                log.info("✓ SD4J pipeline closed successfully");
            } catch (Exception e) {
                log.error("Error closing SD4J pipeline", e);
            }
        }
    }
}
