package com.azure.gpudemo.controller;

import com.azure.gpudemo.service.LangChain4jGpuService;
import com.azure.gpudemo.service.LangChain4jGpuService.ImageStyle;
import com.azure.gpudemo.service.ModelManagementService;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * REST API controller for GPU-accelerated image generation and embeddings.
 */
@Slf4j
@RestController
@RequestMapping("/api/langchain4j")
public class ImageController {

    private final LangChain4jGpuService gpuService;
    private final ModelManagementService modelManagementService;

    public ImageController(LangChain4jGpuService gpuService, 
                          ModelManagementService modelManagementService) {
        this.gpuService = gpuService;
        this.modelManagementService = modelManagementService;
    }

    /**
     * Generate an image using Stable Diffusion with GPU acceleration.
     * 
     * POST /api/langchain4j/image
     * Body: {"prompt": "string", "style": "CLASSIC|HAPPY|CONFUSED|EXCITED"}
     * Returns: PNG image data
     */
    @PostMapping(value = "/image", produces = MediaType.IMAGE_PNG_VALUE)
    public ResponseEntity<byte[]> generateImage(@RequestBody ImageRequest request) {
        log.info("Generating image with prompt: '{}', style: {}", 
            request.getPrompt(), request.getStyle());
        
        try {
            ImageStyle style = ImageStyle.valueOf(request.getStyle().toUpperCase());
            byte[] imageData = gpuService.generateImage(request.getPrompt(), style);
            
            log.info("Successfully generated image: {} bytes", imageData.length);
            return ResponseEntity.ok()
                .contentType(MediaType.IMAGE_PNG)
                .body(imageData);
                
        } catch (IllegalArgumentException e) {
            log.error("Invalid image style: {}", request.getStyle());
            return ResponseEntity.badRequest().build();
        } catch (UnsupportedOperationException e) {
            log.warn("Image generation not yet implemented: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED)
                .body(null);
        } catch (Exception e) {
            log.error("Failed to generate image", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Compare two text strings using embeddings and return similarity score.
     * 
     * POST /api/langchain4j/embeddings
     * Body: {"text1": "string", "text2": "string"}
     * Returns: {"similarity": 0.95, "text1": "...", "text2": "..."}
     */
    @PostMapping(value = "/embeddings", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<EmbeddingResponse> compareEmbeddings(@RequestBody EmbeddingRequest request) {
        log.info("Comparing embeddings for texts (lengths: {}, {})", 
            request.getText1().length(), request.getText2().length());
        
        try {
            double similarity = gpuService.compareEmbeddings(request.getText1(), request.getText2());
            
            EmbeddingResponse response = new EmbeddingResponse();
            response.setSimilarity(similarity);
            response.setText1(request.getText1());
            response.setText2(request.getText2());
            
            log.info("Embedding similarity: {}", similarity);
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to compare embeddings", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get system metrics including GPU status and model information.
     * 
     * GET /api/langchain4j/metrics
     * Returns: {"modelsLoaded": true, "gpuAvailable": true, "models": {...}}
     */
    @GetMapping(value = "/metrics", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> getMetrics() {
        log.debug("Fetching system metrics");
        
        try {
            // Get GPU metrics from service
            Map<String, Object> gpuMetrics = gpuService.getGpuMetrics();
            
            Map<String, Object> metrics = new HashMap<>();
            
            // GPU status - check if GPU is actually enabled (not just available)
            boolean gpuEnabled = gpuMetrics.containsKey("gpuEnabled") && 
                                (Boolean) gpuMetrics.get("gpuEnabled");
            metrics.put("gpuAvailable", gpuEnabled);
            
            // Check if SD4J is ready
            boolean sdReady = gpuMetrics.containsKey("stableDiffusionReady") && 
                            (Boolean) gpuMetrics.get("stableDiffusionReady");
            
            // Models loaded - SD4J ready and embeddings available
            metrics.put("modelsLoaded", sdReady);
            
            // Model details
            Map<String, Object> modelInfo = new HashMap<>();
            
            // Stable Diffusion status from SD4J service
            Map<String, Object> sdInfo = new HashMap<>();
            sdInfo.put("available", sdReady);
            sdInfo.put("status", gpuMetrics.getOrDefault("stableDiffusionStatus", "Not initialized"));
            sdInfo.put("provider", "SD4J (Oracle)");
            modelInfo.put("stableDiffusion", sdInfo);
            
            // Embeddings model (built-in to LangChain4j)
            Map<String, Object> embInfo = new HashMap<>();
            embInfo.put("available", true);
            embInfo.put("model", "All-MiniLM-L6-v2");
            embInfo.put("provider", "LangChain4j (HuggingFace)");
            modelInfo.put("allMiniLmL6V2", embInfo);
            
            metrics.put("models", modelInfo);
            metrics.put("onnxRuntimeVersion", gpuMetrics.getOrDefault("onnxRuntimeVersion", "Unknown"));
            
            return ResponseEntity.ok(metrics);
            
        } catch (Exception e) {
            log.error("Failed to fetch metrics", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Health check endpoint.
     * 
     * GET /api/langchain4j/health
     * Returns: {"status": "UP"}
     */
    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }

    @Data
    public static class ImageRequest {
        private String prompt;
        private String style = "CLASSIC";
    }

    @Data
    public static class EmbeddingRequest {
        private String text1;
        private String text2;
    }

    @Data
    public static class EmbeddingResponse {
        private double similarity;
        private String text1;
        private String text2;
    }
}
