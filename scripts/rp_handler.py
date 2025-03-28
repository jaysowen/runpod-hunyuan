import runpod
import json
import time
import os
import requests
import base64
from io import BytesIO
from PIL import Image, ImageFilter # Keep PIL for potential future thumbnailing if needed
from b2sdk.v2 import B2Api, InMemoryAccountInfo, UploadMode, Bucket
from b2sdk.v2.exception import B2Error
import hashlib
from typing import Dict, List, Optional, Tuple, Any, Union

# --- Constants ---
# (Keep existing constants like timeouts, retries, ComfyUI host, RunPod config)
# ...

# ComfyUI Configuration
COMFY_HOST = os.environ.get("COMFY_HOST", "127.0.0.1:8188")
COMFY_BASE_URL = f"http://{COMFY_HOST}"
COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")

# B2 Configuration (Ensure these are set if you need video output)
B2_ENABLED = bool(os.environ.get("BUCKET_ACCESS_KEY_ID"))
B2_BUCKET_NAME = os.environ.get('BUCKET_NAME')
B2_APP_KEY_ID = os.environ.get('BUCKET_ACCESS_KEY_ID')
B2_APP_KEY = os.environ.get('BUCKET_SECRET_ACCESS_KEY')
B2_ENDPOINT_URL = os.environ.get("BUCKET_ENDPOINT_URL", '') # Should NOT end with a slash

# Supported Video Extensions (add more if needed)
SUPPORTED_VIDEO_EXTENSIONS = {".mp4", ".webm", ".gif", ".avi", ".mov"}

# --- Helper Functions ---
# (validate_input, check_server, download_image, upload_input_images,
#  queue_workflow, get_history remain largely the same)
# ... (Keep the existing versions of these) ...

# --- B2 Upload Functions ---
# (_initialize_b2, upload_file_to_b2, upload_bytes_to_b2 remain the same)
# ... (Keep the existing versions of these) ...

# --- Output Processing (Modified for Video) ---

def _find_output_file_path(outputs: Dict, desired_extensions: set) -> Optional[str]:
    """
    Finds the first output file matching desired extensions from ComfyUI history outputs.

    Args:
        outputs: The dictionary containing node outputs from ComfyUI history.
        desired_extensions: A set of lowercase file extensions to look for (e.g., {".mp4", ".gif"}).

    Returns:
        The full local path to the first matching output file found, or None.
    """
    print(f"runpod-worker-comfy - Searching for output file with extensions: {desired_extensions}")
    # Common keys where ComfyUI might place output files/videos
    possible_output_keys = ["gifs", "videos", "files", "images"] # Check images last as fallback?

    for node_id, node_output in outputs.items():
        if not isinstance(node_output, dict):
            continue
        for key in possible_output_keys:
            if key in node_output and isinstance(node_output[key], list):
                for file_info in node_output[key]:
                    if isinstance(file_info, dict) and "filename" in file_info:
                        filename = file_info["filename"]
                        _ , ext = os.path.splitext(filename)
                        if ext.lower() in desired_extensions:
                            # Construct the full path relative to the ComfyUI base directory
                            relative_path = os.path.join(file_info.get("subfolder", ""), filename)
                            full_path = os.path.join(COMFY_OUTPUT_PATH, relative_path)
                            if os.path.exists(full_path):
                                print(f"runpod-worker-comfy - Found matching output file: {full_path}")
                                return full_path
                            else:
                                print(f"runpod-worker-comfy - Warning: Output file path reported but not found: {full_path}")
    print(f"runpod-worker-comfy - No output file found matching extensions {desired_extensions}.")
    return None

# REMOVED: _create_and_upload_blur - No blurring for video by default

def process_comfyui_output(outputs: Dict, job_id: str) -> Dict[str, Any]:
    """
    Processes the first found video output file: uploads to B2 (if configured).

    Args:
        outputs: The 'outputs' dictionary from the ComfyUI history for the prompt.
        job_id: The RunPod job ID.

    Returns:
        A dictionary with 'status', and 'url' (URL to the video in B2).
    """
    # Prioritize searching for video files
    local_file_path = _find_output_file_path(outputs, SUPPORTED_VIDEO_EXTENSIONS)

    if not local_file_path:
        return {
            "status": "error",
            "message": f"Could not find generated video file ({'/'.join(SUPPORTED_VIDEO_EXTENSIONS)}) in ComfyUI output.",
        }

    if not B2_ENABLED:
        print("runpod-worker-comfy - ERROR: B2 is not configured. Cannot upload video output.")
        return {
            "status": "error",
            "message": "Output generated, but B2 storage is not configured for upload.",
         }

    # Proceed with B2 upload
    b2_api, bucket = _initialize_b2()
    if not b2_api or not bucket:
        return {
            "status": "error",
            "message": "B2 is configured but failed to initialize. Cannot upload video.",
        }

    # Upload the video file
    base_filename = os.path.basename(local_file_path)
    # Store videos in a specific subfolder if desired, e.g., 'videos/'
    b2_video_path = f"{job_id}/videos/{base_filename}"
    video_url = upload_file_to_b2(b2_api, bucket, local_file_path, b2_video_path)

    if not video_url:
        return {
            "status": "error",
            "message": "Failed to upload video output to B2.",
        }

    print(f"runpod-worker-comfy - Video uploaded successfully to B2: {video_url}")
    return {
        "status": "success",
        "url": video_url, # URL of the uploaded video
    }


# --- Main Handler (Modified Return Structure) ---

def handler(job: Dict) -> Dict:
    """
    RunPod serverless handler function for ComfyUI image or video generation.
    """
    job_id = job.get("id", "unknown_job")
    print(f"\nrunpod-worker-comfy - Starting job {job_id}")

    job_input = job.get("input")

    # 1. Validate Input (remains the same)
    validated_data, error_message = validate_input(job_input)
    if error_message:
        print(f"runpod-worker-comfy - Input validation failed: {error_message}")
        return {"error": error_message, "refresh_worker": False}
    workflow = validated_data["workflow"]
    input_images = validated_data.get("images")
    print("runpod-worker-comfy - Input validation successful.")

    # 2. Check ComfyUI Server Availability (remains the same)
    if not check_server(COMFY_BASE_URL):
        return {"error": f"ComfyUI server at {COMFY_BASE_URL} is not available.", "refresh_worker": False}

    # 3. Upload Input Images (if any) (remains the same)
    if input_images:
        upload_result = upload_input_images(input_images)
        if upload_result["status"] == "error":
            print(f"runpod-worker-comfy - Error uploading input images: {upload_result['message']}")
            return {"error": f"Failed to upload one or more input images. Details: {upload_result.get('details', 'N/A')}", "refresh_worker": False}

    # 4. Queue Workflow (remains the same)
    try:
        print("runpod-worker-comfy - Queuing workflow...")
        queue_response = queue_workflow(workflow)
        prompt_id = queue_response.get("prompt_id")
        if not prompt_id:
             return {"error": f"Failed to queue workflow. Response: {queue_response}", "refresh_worker": True}
        print(f"runpod-worker-comfy - Workflow queued successfully. Prompt ID: {prompt_id}")
    except requests.exceptions.RequestException as e:
        return {"error": f"Error queuing workflow (network request failed): {str(e)}", "refresh_worker": True}
    except json.JSONDecodeError as e:
        return {"error": f"Error queuing workflow (invalid JSON response): {str(e)}", "refresh_worker": True}
    except Exception as e:
        return {"error": f"Unexpected error queuing workflow: {str(e)}", "refresh_worker": True}

    # 5. Poll for Results (remains the same logic)
    print(f"runpod-worker-comfy - Polling for results for prompt {prompt_id}...")
    final_history = None
    # ... (Keep the existing polling loop) ...
    for i in range(COMFY_POLLING_MAX_RETRIES):
        try:
            history = get_history(prompt_id)
            prompt_history = history.get(prompt_id)
            if prompt_history and prompt_history.get("outputs"):
                print(f"runpod-worker-comfy - Workflow execution finished after {i+1} poll(s).")
                final_history = prompt_history
                break
            # ... (rest of polling logic) ...
        except Exception as e:
             print(f"runpod-worker-comfy - Warning: Unexpected error during history polling (attempt {i+1}): {str(e)}")
        time.sleep(COMFY_POLLING_INTERVAL_MS / 1000.0)
    else: # Max retries reached
        print(f"runpod-worker-comfy - Max retries ({COMFY_POLLING_MAX_RETRIES}) reached while waiting for results.")
        return {"error": "Processing timed out.", "refresh_worker": True}

    if not final_history or not final_history.get("outputs"):
        return {"error": "Workflow completed but no outputs found in history.", "refresh_worker": True}

    # 6. Process Output File (Video or Image) using the modified function
    print("runpod-worker-comfy - Processing output file...")
    output_result = process_comfyui_output(final_history["outputs"], job_id)

    # 7. Format and Return Result
    if output_result["status"] == "error":
        print(f"runpod-worker-comfy - Error processing output file: {output_result['message']}")
        return {"error": output_result["message"], "refresh_worker": True}

    print(f"runpod-worker-comfy - Job {job_id} completed successfully.")
    # Return the video URL using a clear key
    final_output = {
        "video_url": output_result["url"],
        "refresh_worker": REFRESH_WORKER
    }

    # Return only non-None values if needed, though here it's simpler
    return final_output


# --- RunPod Serverless Entry Point ---
if __name__ == "__main__":
    print("runpod-worker-comfy - Starting RunPod Serverless Worker...")
    runpod.serverless.start({"handler": handler})