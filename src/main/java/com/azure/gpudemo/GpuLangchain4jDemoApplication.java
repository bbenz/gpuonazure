package com.azure.gpudemo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;

/**
 * Main Spring Boot application for GPU-accelerated LangChain4j demo.
 * 
 * This application demonstrates:
 * - GPU-accelerated image generation using Stable Diffusion v1.5 ONNX
 * - GPU-accelerated embeddings using All-MiniLM-L6-v2 ONNX
 * - LangChain4j integration with ONNX Runtime
 * - Deployment on Azure Container Apps with GPU workload profiles
 */
@SpringBootApplication
@EnableAsync
public class GpuLangchain4jDemoApplication {

    public static void main(String[] args) {
        // Log GPU availability on startup
        System.out.println("=".repeat(80));
        System.out.println("GPU-Accelerated LangChain4j Demo Starting...");
        System.out.println("=".repeat(80));
        
        try {
            // Check CUDA availability
            String cudaPath = System.getenv("CUDA_PATH");
            System.out.println("CUDA_PATH: " + (cudaPath != null ? cudaPath : "Not set"));
            System.out.println("LD_LIBRARY_PATH: " + System.getenv("LD_LIBRARY_PATH"));
        } catch (Exception e) {
            System.err.println("Warning: Unable to check GPU environment: " + e.getMessage());
        }
        
        SpringApplication.run(GpuLangchain4jDemoApplication.class, args);
        
        System.out.println("=".repeat(80));
        System.out.println("Application started successfully!");
        System.out.println("Access the demo at: http://localhost:8080");
        System.out.println("=".repeat(80));
    }

    /**
     * Configure async executor for image generation tasks.
     * Uses virtual threads (Java 21) for efficient concurrent processing.
     */
    @Bean(name = "imageGenerationExecutor")
    public Executor imageGenerationExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(4);
        executor.setQueueCapacity(10);
        executor.setThreadNamePrefix("image-gen-");
        executor.initialize();
        return executor;
    }
}
