// API base URL
const API_BASE = '/api/langchain4j';

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    loadMetrics();
    setupImageForm();
    setupEmbeddingForm();
    
    // Refresh metrics every 30 seconds
    setInterval(loadMetrics, 30000);
});

/**
 * Load and display system metrics
 */
async function loadMetrics() {
    try {
        const response = await fetch(`${API_BASE}/metrics`);
        if (!response.ok) throw new Error('Failed to load metrics');
        
        const data = await response.json();
        
        // Update GPU status
        updateMetric('gpu-status', data.gpuAvailable ? 'Available ✅' : 'Not Available ❌', data.gpuAvailable);
        
        // Update models status
        updateMetric('models-status', data.modelsLoaded ? 'Loaded ✅' : 'Not Loaded ❌', data.modelsLoaded);
        
        // Update Stable Diffusion status
        const sdAvailable = data.models.stableDiffusion?.available;
        const sdSize = formatBytes(data.models.stableDiffusion?.sizeBytes || 0);
        updateMetric('sd-status', sdAvailable ? `Ready (${sdSize}) ✅` : 'Not Available ❌', sdAvailable);
        
        // Update Embeddings model status
        const embAvailable = data.models.allMiniLmL6V2?.available;
        const embSize = formatBytes(data.models.allMiniLmL6V2?.sizeBytes || 0);
        updateMetric('embedding-status', embAvailable ? `Ready (${embSize}) ✅` : 'Not Available ❌', embAvailable);
        
    } catch (error) {
        console.error('Error loading metrics:', error);
        updateMetric('gpu-status', 'Error ❌', false);
        updateMetric('models-status', 'Error ❌', false);
        updateMetric('sd-status', 'Error ❌', false);
        updateMetric('embedding-status', 'Error ❌', false);
    }
}

/**
 * Update a metric display
 */
function updateMetric(elementId, text, isHealthy) {
    const element = document.getElementById(elementId);
    element.textContent = text;
    element.classList.remove('loading', 'error');
    if (!isHealthy) {
        element.classList.add('error');
    }
}

/**
 * Format bytes to human-readable string
 */
function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

/**
 * Format duration from milliseconds to MM:SS or SS.Xs format
 */
function formatDuration(ms) {
    if (ms < 1000) {
        // Less than 1 second - show milliseconds
        return `${ms}ms`;
    } else if (ms < 60000) {
        // Less than 1 minute - show seconds with 1 decimal
        const seconds = (ms / 1000).toFixed(1);
        return `${seconds}s`;
    } else {
        // 1 minute or more - show MM:SS
        const minutes = Math.floor(ms / 60000);
        const seconds = Math.floor((ms % 60000) / 1000);
        return `${minutes}m ${seconds}s`;
    }
}

/**
 * Setup image generation form
 */
function setupImageForm() {
    const form = document.getElementById('image-form');
    const promptInput = document.getElementById('prompt');
    const styleSelect = document.getElementById('style');
    const resultContainer = document.getElementById('image-result');
    const imageElement = document.getElementById('generated-image');
    const timeElement = document.getElementById('generation-time');
    const errorContainer = document.getElementById('image-error');
    const submitButton = form.querySelector('button[type="submit"]');
    
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        const prompt = promptInput.value.trim();
        const style = styleSelect.value;
        
        if (!prompt) {
            showError(errorContainer, 'Please enter a prompt');
            return;
        }
        
        // Show loading state
        setButtonLoading(submitButton, true);
        hideElement(resultContainer);
        hideElement(errorContainer);
        
        const startTime = Date.now();
        
        try {
            const response = await fetch(`${API_BASE}/image`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ prompt, style })
            });
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            const blob = await response.blob();
            const imageUrl = URL.createObjectURL(blob);
            
            const endTime = Date.now();
            const duration = endTime - startTime;
            
            // Display result
            imageElement.src = imageUrl;
            timeElement.textContent = formatDuration(duration);
            showElement(resultContainer);
            
        } catch (error) {
            console.error('Error generating image:', error);
            const status = error.message?.includes('501') || error.message?.includes('NOT_IMPLEMENTED') ? 501 : 500;
            if (status === 501) {
                showError(errorContainer, 
                    '🚧 Stable Diffusion image generation is not yet fully implemented. ' +
                    'This requires CLIP tokenizer, U-Net, and VAE decoder integration. ' +
                    'Try the embeddings comparison instead - it works great! 🎉');
            } else {
                showError(errorContainer, 'Failed to generate image. Please try again.');
            }
        } finally {
            setButtonLoading(submitButton, false);
        }
    });
}

/**
 * Setup embeddings comparison form
 */
function setupEmbeddingForm() {
    const form = document.getElementById('embedding-form');
    const text1Input = document.getElementById('text1');
    const text2Input = document.getElementById('text2');
    const resultContainer = document.getElementById('embedding-result');
    const valueElement = document.getElementById('similarity-value');
    const barElement = document.getElementById('similarity-bar');
    const timeElement = document.getElementById('embedding-time');
    const errorContainer = document.getElementById('embedding-error');
    const submitButton = form.querySelector('button[type="submit"]');
    
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        const text1 = text1Input.value.trim();
        const text2 = text2Input.value.trim();
        
        if (!text1 || !text2) {
            showError(errorContainer, 'Please enter both texts');
            return;
        }
        
        // Show loading state
        setButtonLoading(submitButton, true);
        hideElement(resultContainer);
        hideElement(errorContainer);
        
        const startTime = Date.now();
        
        try {
            const response = await fetch(`${API_BASE}/embeddings`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ text1, text2 })
            });
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            const data = await response.json();
            const endTime = Date.now();
            const duration = endTime - startTime;
            
            // Display result
            const similarity = data.similarity;
            valueElement.textContent = similarity.toFixed(4);
            barElement.style.width = `${similarity * 100}%`;
            timeElement.textContent = formatDuration(duration);
            showElement(resultContainer);
            
        } catch (error) {
            console.error('Error comparing embeddings:', error);
            showError(errorContainer, 'Failed to compare embeddings. Please try again.');
        } finally {
            setButtonLoading(submitButton, false);
        }
    });
}

/**
 * Set button loading state
 */
function setButtonLoading(button, isLoading) {
    const textSpan = button.querySelector('.btn-text');
    const spinner = button.querySelector('.spinner');
    
    if (isLoading) {
        button.disabled = true;
        textSpan.style.display = 'none';
        spinner.style.display = 'inline';
    } else {
        button.disabled = false;
        textSpan.style.display = 'inline';
        spinner.style.display = 'none';
    }
}

/**
 * Show error message
 */
function showError(container, message) {
    container.textContent = message;
    showElement(container);
}

/**
 * Show element
 */
function showElement(element) {
    element.style.display = 'block';
}

/**
 * Hide element
 */
function hideElement(element) {
    element.style.display = 'none';
}
