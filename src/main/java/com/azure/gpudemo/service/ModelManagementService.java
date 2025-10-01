package com.azure.gpudemo.service;

import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtSession;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.HexFormat;

/**
 * Service for managing ONNX model downloads, caching, and validation.
 * Ensures models are available locally before inference.
 */
@Slf4j
@Service
public class ModelManagementService {

    @Value("${langchain4j.models.base-path}")
    private String modelsBasePath;

    @Value("${models.download.enabled:true}")
    private boolean downloadEnabled;

    @Value("${models.download.azure-storage-account:gpudemostorage}")
    private String azureStorageAccount;

    @Value("${models.download.azure-container:onnx-models}")
    private String azureContainer;

    private final OrtEnvironment ortEnvironment;

    public ModelManagementService(OrtEnvironment ortEnvironment) {
        this.ortEnvironment = ortEnvironment;
    }

    @PostConstruct
    public void initializeModels() {
        log.info("Initializing model management service");
        createModelDirectories();
        
        if (downloadEnabled) {
            log.info("Model download enabled, checking for required models");
            ensureModelsAvailable();
        } else {
            log.info("Model download disabled, assuming models are pre-loaded");
            validateExistingModels();
        }
    }

    private void createModelDirectories() {
        try {
            Path basePath = Path.of(modelsBasePath);
            if (!Files.exists(basePath)) {
                Files.createDirectories(basePath);
                log.info("Created model directory: {}", basePath);
            }
        } catch (IOException e) {
            log.error("Failed to create model directories", e);
            throw new RuntimeException("Cannot create model directories", e);
        }
    }

    private void ensureModelsAvailable() {
        // Check and download Stable Diffusion v1.5
        String sdModelPath = modelsBasePath + "/stable-diffusion/model.onnx";
        if (!Files.exists(Path.of(sdModelPath))) {
            log.info("Stable Diffusion model not found, downloading...");
            downloadModel(
                "stable-diffusion-v1-5.onnx",
                sdModelPath,
                "https://" + azureStorageAccount + ".blob.core.windows.net/" + azureContainer + "/stable-diffusion-v1-5.onnx"
            );
        } else {
            log.info("Stable Diffusion model found at: {}", sdModelPath);
        }

        // Check and download All-MiniLM-L6-v2
        String embeddingModelPath = modelsBasePath + "/all-MiniLM-L6-v2/model.onnx";
        if (!Files.exists(Path.of(embeddingModelPath))) {
            log.info("Embedding model not found, downloading...");
            downloadModel(
                "all-MiniLM-L6-v2.onnx",
                embeddingModelPath,
                "https://" + azureStorageAccount + ".blob.core.windows.net/" + azureContainer + "/all-MiniLM-L6-v2.onnx"
            );
        } else {
            log.info("Embedding model found at: {}", embeddingModelPath);
        }
    }

    private void downloadModel(String modelName, String destinationPath, String downloadUrl) {
        log.info("Downloading {} from {}", modelName, downloadUrl);
        
        try {
            URL url = new URL(downloadUrl);
            Path destination = Path.of(destinationPath);
            Path tempFile = Files.createTempFile("model-download-", ".onnx");
            
            try (InputStream in = url.openStream()) {
                long bytesDownloaded = Files.copy(in, tempFile, StandardCopyOption.REPLACE_EXISTING);
                log.info("Downloaded {} bytes for {}", bytesDownloaded, modelName);
            }
            
            // Move to final destination
            Files.move(tempFile, destination, StandardCopyOption.REPLACE_EXISTING);
            log.info("Successfully downloaded and installed {} to {}", modelName, destinationPath);
            
            // Validate the downloaded model
            validateModel(destinationPath);
            
        } catch (IOException e) {
            log.error("Failed to download model: " + modelName, e);
            throw new RuntimeException("Model download failed: " + modelName, e);
        }
    }

    private void validateExistingModels() {
        // Validate SD4J directory structure (SD4J handles model loading internally)
        String sdBasePath = modelsBasePath + "/stable-diffusion";
        File sdBaseDir = new File(sdBasePath);
        
        if (!sdBaseDir.exists() || !sdBaseDir.isDirectory()) {
            log.warn("Stable Diffusion directory not found: {}", sdBasePath);
            log.warn("SD4J will initialize models lazily on first use");
        } else {
            log.info("Stable Diffusion base directory found: {}", sdBasePath);
            
            // Check for SD4J subdirectories (text_encoder, unet, vae_decoder)
            String[] requiredDirs = {"text_encoder", "unet", "vae_decoder"};
            for (String dir : requiredDirs) {
                File subDir = new File(sdBasePath + "/" + dir);
                if (subDir.exists() && subDir.isDirectory()) {
                    log.info("  ✓ Found {} directory", dir);
                } else {
                    log.warn("  ⚠ Missing {} directory (SD4J requires this)", dir);
                }
            }
        }
        
        // Note: Embedding model (All-MiniLM-L6-v2) is packaged with LangChain4j, no validation needed
        log.info("✓ Model validation completed (SD4J uses lazy initialization)");
    }

    /**
     * Validate a single ONNX model file by attempting to load it.
     * This is optional - SD4J handles its own validation and lazy loading.
     * 
     * @param modelPath Path to the ONNX model file
     * @return true if model is valid, false otherwise
     */
    private boolean validateModel(String modelPath) {
        File modelFile = new File(modelPath);
        
        if (!modelFile.exists()) {
            log.warn("Model file does not exist: {}", modelPath);
            return false;
        }
        
        long fileSizeBytes = modelFile.length();
        long fileSizeMB = fileSizeBytes / (1024 * 1024);
        log.info("Model {} size: {} MB", modelFile.getName(), fileSizeMB);
        
        // Optionally validate model can be loaded by ONNX Runtime (CPU mode)
        // Skip validation for large models to avoid long startup times
        if (fileSizeMB > 500) {
            log.info("Skipping validation for large model ({}MB): {}", fileSizeMB, modelFile.getName());
            return true;
        }
        
        try {
            OrtSession.SessionOptions options = new OrtSession.SessionOptions();
            // Use default CPU execution provider for validation
            // GPU execution will be configured separately in the main configuration
            
            try (OrtSession session = ortEnvironment.createSession(modelPath, options)) {
                log.info("Successfully validated model: {} (inputs: {}, outputs: {})",
                    modelFile.getName(),
                    session.getInputNames().size(),
                    session.getOutputNames().size()
                );
                return true;
            }
        } catch (Exception e) {
            log.warn("Model validation failed for: {} - {}", modelPath, e.getMessage());
            return false;
        }
    }

    public String computeChecksum(String filePath) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] fileBytes = Files.readAllBytes(Path.of(filePath));
            byte[] hashBytes = digest.digest(fileBytes);
            return HexFormat.of().formatHex(hashBytes);
        } catch (Exception e) {
            log.error("Failed to compute checksum for: " + filePath, e);
            return null;
        }
    }

    public boolean isModelAvailable(String modelName) {
        String modelPath = modelsBasePath + "/" + modelName;
        return Files.exists(Path.of(modelPath));
    }

    public long getModelSize(String modelName) {
        String modelPath = modelsBasePath + "/" + modelName;
        try {
            return Files.size(Path.of(modelPath));
        } catch (IOException e) {
            log.error("Failed to get model size for: " + modelName, e);
            return -1;
        }
    }
}
