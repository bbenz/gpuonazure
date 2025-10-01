package com.azure.gpudemo.service;

import ai.onnxruntime.*;
import dev.langchain4j.data.embedding.Embedding;
import dev.langchain4j.model.embedding.EmbeddingModel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.FloatBuffer;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.CompletableFuture;

/**
 * Core service for GPU-accelerated inference using LangChain4j and ONNX Runtime.
 * 
 * Capabilities:
 * 1. Generate cartoon images using Stable Diffusion v1.5 ONNX
 * 2. Compute embeddings using All-MiniLM-L6-v2 ONNX
 * 3. Compare semantic similarity between texts
 * 4. GPU-accelerated processing for 10-15x speedup
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class LangChain4jGpuService {

    /**
     * Art style variants for image generation.
     */
    public enum ImageStyle {
        CLASSIC,    // Classic professional style
        HAPPY,      // Cheerful, smiling style
        CONFUSED,   // Puzzled, questioning style
        EXCITED     // Enthusiastic, energetic style
    }

    private final EmbeddingModel embeddingModel;
    private final SD4JImageGenerationService sd4jService;
    private final OrtEnvironment ortEnvironment;
    private final OrtSession.SessionOptions sessionOptions;

    /**
     * Generate image with style preset (synchronous wrapper).
     * 
     * Now powered by Oracle's SD4J (Stable Diffusion for Java) - a complete,
     * production-ready implementation with CLIP tokenizer, U-Net, VAE decoder,
     * and multiple scheduling algorithms!
     * 
     * @param prompt Text description of the desired image
     * @param style ImageStyle enum (CLASSIC, HAPPY, CONFUSED, EXCITED)
     * @return PNG image as byte array
     */
    public byte[] generateImage(String prompt, ImageStyle style) {
        log.info("Generating image with prompt: '{}', style: {}", prompt, style);
        
        try {
            // Enhance prompt with style-specific details
            String enhancedPrompt = buildImagePrompt(prompt, style);
            String negativePrompt = "blurry, low quality, distorted, ugly, bad anatomy, low resolution";
            
            // Generate image using SD4J
            // Parameters tuned for good quality cartoon images
            return sd4jService.generateImage(
                enhancedPrompt,
                negativePrompt,
                40,      // 40 steps = good quality/speed balance
                7.5f,    // Standard guidance scale
                42,      // Fixed seed for consistency
                512,     // SD 1.5 native resolution
                512
            );
            
        } catch (Exception e) {
            log.error("Failed to generate image", e);
            throw new RuntimeException("Image generation failed: " + e.getMessage(), e);
        }
    }

    /**
     * Build an enhanced prompt for image generation.
     * Adds style-specific adjectives and quality enhancers.
     */
    private String buildImagePrompt(String userPrompt, ImageStyle style) {
        StringBuilder prompt = new StringBuilder();
        
        // Add style-specific prefix
        switch (style) {
            case CLASSIC:
                prompt.append("professional, classic cartoon style, ");
                break;
            case HAPPY:
                prompt.append("cheerful, smiling, joyful character, ");
                break;
            case CONFUSED:
                prompt.append("puzzled, questioning, confused character, ");
                break;
            case EXCITED:
                prompt.append("enthusiastic, energetic, excited character, ");
                break;
        }
        
        // Add user's custom description
        prompt.append(userPrompt);
        
        // Add quality enhancers
        prompt.append(", cartoon style illustration, digital art, clean background, high quality, detailed, friendly");
        
        String finalPrompt = prompt.toString();
        log.info("Enhanced prompt: {}", finalPrompt);
        return finalPrompt;
    }

    /**
     * Legacy async method - no longer used since SD4J handles async internally.
     * Kept for backward compatibility but delegates to synchronous SD4J method.
     * 
     * @deprecated Use generateImage(String prompt, ImageStyle style) instead
     */
    @Deprecated
    @Async("imageGenerationExecutor")
    public CompletableFuture<byte[]> generateImageAsync(String prompt, 
                                                           int numInferenceSteps, 
                                                           double guidanceScale) {
        log.warn("Using deprecated async method - consider using generateImage(prompt, style) instead");
        
        // Delegate to SD4J with default CLASSIC style
        try {
            byte[] result = generateImage(prompt, ImageStyle.CLASSIC);
            return CompletableFuture.completedFuture(result);
        } catch (Exception e) {
            return CompletableFuture.failedFuture(e);
        }
    }

    /**
     * Compute embeddings for a list of texts using GPU-accelerated model.
     * Expected speedup: ~10x on GPU vs CPU
     * 
     * @param texts List of text strings to embed
     * @return List of 384-dimensional embeddings
     */
    public List<Embedding> computeEmbeddings(List<String> texts) {
        log.info("Computing embeddings for {} texts", texts.size());
        long startTime = System.currentTimeMillis();
        
        try {
            // Convert strings to TextSegments
            List<dev.langchain4j.data.segment.TextSegment> segments = texts.stream()
                .map(dev.langchain4j.data.segment.TextSegment::from)
                .toList();
            List<Embedding> embeddings = embeddingModel.embedAll(segments).content();
            
            long duration = System.currentTimeMillis() - startTime;
            log.info("✓ Embeddings computed in {} ms", duration);
            log.info("Average time per text: {} ms", duration / texts.size());
            
            return embeddings;
        } catch (Exception e) {
            log.error("Failed to compute embeddings: {}", e.getMessage(), e);
            throw new RuntimeException("Embedding computation failed", e);
        }
    }

    /**
     * Compare embeddings of two texts (alias for compareSemanticSimilarity).
     * 
     * @param text1 First text
     * @param text2 Second text
     * @return Cosine similarity score between -1 and 1
     */
    public double compareEmbeddings(String text1, String text2) {
        return compareSemanticSimilarity(text1, text2);
    }

    /**
     * Compare semantic similarity between two texts.
     * Returns cosine similarity score between -1 and 1.
     * 
     * @param text1 First text
     * @param text2 Second text
     * @return Cosine similarity score (higher = more similar)
     */
    public double compareSemanticSimilarity(String text1, String text2) {
        log.info("Comparing similarity between: '{}' and '{}'", text1, text2);
        
        List<Embedding> embeddings = computeEmbeddings(List.of(text1, text2));
        
        double similarity = cosineSimilarity(
            embeddings.get(0).vector(),
            embeddings.get(1).vector()
        );
        
        log.info("Similarity score: {}", similarity);
        return similarity;
    }

    /**
     * OLD HELPER METHODS - No longer needed since SD4J handles all of this internally.
     * SD4J includes proper CLIP tokenization, timestep scheduling, tensor conversion, etc.
     * Keeping these as comments for reference/educational purposes.
     * 
     * What SD4J does for you:
     * - CLIP tokenization (proper BPE tokenizer, not hash-based)
     * - Timestep scheduling (LMS Discrete, Euler Ancestral)
     * - Tensor format conversion (NCHW, normalization, denormalization)
     * - U-Net inference with proper attention mechanisms
     * - VAE decoding from latent space to pixels
     * - Optional safety checking
     */

    /**
     * Calculate cosine similarity between two vectors.
     */
    private double cosineSimilarity(float[] vec1, float[] vec2) {
        double dotProduct = 0.0;
        double norm1 = 0.0;
        double norm2 = 0.0;
        
        for (int i = 0; i < vec1.length; i++) {
            dotProduct += vec1[i] * vec2[i];
            norm1 += vec1[i] * vec1[i];
            norm2 += vec2[i] * vec2[i];
        }
        
        return dotProduct / (Math.sqrt(norm1) * Math.sqrt(norm2));
    }

    /**
     * Get GPU metrics for monitoring.
     */
    public Map<String, Object> getGpuMetrics() {
        Map<String, Object> metrics = new HashMap<>();
        
        try {
            // Get SD4J status
            metrics.put("stableDiffusionProvider", "SD4J (Oracle)");
            metrics.put("stableDiffusionReady", sd4jService.isReady());
            metrics.put("stableDiffusionStatus", sd4jService.getStatus());
            
            // Get ONNX Runtime info
            metrics.put("onnxRuntimeVersion", ortEnvironment.getVersion());
            metrics.put("gpuEnabled", sessionOptions != null);
            
        } catch (Exception e) {
            log.error("Failed to get GPU metrics: {}", e.getMessage());
            metrics.put("error", e.getMessage());
        }
        
        return metrics;
    }
}
