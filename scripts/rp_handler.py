import runpod
import json
import time
import os
import requests
import base64
from io import BytesIO
from PIL import Image
from b2sdk.v2 import B2Api, InMemoryAccountInfo, UploadMode
import subprocess
import tempfile
import torch
import gc
import glob

# --- Allowlist specific classes for torch.load (PyTorch >= 1.13+) ---
try:
    import ultralytics.nn.tasks
    # Check if the function exists for compatibility
    if hasattr(torch.serialization, 'add_safe_globals'):
        # Allow loading ultralytics DetectionModel needed by some .pt files
        torch.serialization.add_safe_globals([ultralytics.nn.tasks.DetectionModel])
        print("runpod-worker-comfy - Added ultralytics.nn.tasks.DetectionModel to safe globals for torch.load.")
    else:
        print("runpod-worker-comfy - torch.serialization.add_safe_globals not found (likely older PyTorch version).")
except ImportError:
    print("runpod-worker-comfy - ultralytics not found, skipping safe global addition.")
except Exception as e:
    print(f"runpod-worker-comfy - Warning: Failed to add ultralytics safe global: {e}")
# --- End Allowlist ---

# --- 配置常量 ---
# ComfyUI API 检查的时间间隔（毫秒）
COMFY_API_AVAILABLE_INTERVAL_MS = 50
# ComfyUI API 检查的最大重试次数
COMFY_API_AVAILABLE_MAX_RETRIES = 500
# 轮询结果的时间间隔（毫秒）
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
# 轮询结果的最大重试次数
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 1000)) # 稍微增加轮询次数
# ComfyUI 服务器地址
COMFY_HOST = "127.0.0.1:8188"
# 是否在每个作业完成后刷新工作器状态
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"
# 图片模糊处理的半径
IMAGE_FILTER_BLUR_RADIUS = int(os.environ.get("IMAGE_FILTER_BLUR_RADIUS", 10))
# 统一 ComfyUI 输出目录
COMFYUI_OUTPUT_PATH = os.environ.get("COMFYUI_OUTPUT_PATH", "/workspace/ComfyUI/output")
SUPPORTED_VIDEO_FORMATS = ['.mp4', '.webm', '.avi', '.gif'] # 添加 gif 支持
# Job timeout in seconds
JOB_TIMEOUT_SECONDS = 600 # 10 minutes

# --- B2 API 全局实例 ---
b2_api_instance = None
b2_bucket_instance = None

def initialize_b2():
    """初始化 B2 API 客户端和存储桶实例"""
    global b2_api_instance, b2_bucket_instance
    # 如果已经初始化或未配置B2，则跳过
    if b2_api_instance and b2_bucket_instance:
        return True
    if not os.environ.get('BUCKET_ACCESS_KEY_ID'):
        print("runpod-worker-comfy - B2 credentials not configured. Skipping B2 initialization.")
        return False

    try:
        print("runpod-worker-comfy - Initializing B2 API...")
        info = InMemoryAccountInfo()
        api = B2Api(info)
        application_key_id = os.environ.get('BUCKET_ACCESS_KEY_ID')
        application_key = os.environ.get('BUCKET_SECRET_ACCESS_KEY')
        api.authorize_account("production", application_key_id, application_key)
        bucket_name = os.environ.get('BUCKET_NAME')
        bucket = api.get_bucket_by_name(bucket_name)
        b2_api_instance = api
        b2_bucket_instance = bucket
        print("runpod-worker-comfy - B2 API Initialized Successfully.")
        return True
    except Exception as e:
        print(f"runpod-worker-comfy - Failed to initialize B2 API: {str(e)}")
        b2_api_instance = None
        b2_bucket_instance = None
        return False

def upload_to_b2(local_file_path, file_name):
    """将文件上传到 B2 存储"""
    if not b2_bucket_instance:
        error_msg = "B2 Bucket 未初始化，请检查配置"
        print(f"runpod-worker-comfy - {error_msg}")
        return None

    try:
        endpoint_url = os.environ.get("BUCKET_ENDPOINT_URL", '')
        bucket_name = os.environ.get('BUCKET_NAME')
        
        if not endpoint_url or not bucket_name:
            error_msg = "缺少必要的 B2 配置"
            print(f"runpod-worker-comfy - {error_msg}")
            return None

        # 检查文件是否存在且可读
        if not os.path.exists(local_file_path):
            return None
            
        if not os.access(local_file_path, os.R_OK):
            return None

        # 检查文件是否为空
        if os.path.getsize(local_file_path) == 0:
            return None

        # 使用标准上传模式
        uploaded_file = b2_bucket_instance.upload_local_file(
            local_file=local_file_path,
            file_name=file_name
        )

        download_url = f"{endpoint_url}/{bucket_name}/{file_name}"
        return download_url

    except Exception as e:
        print(f"runpod-worker-comfy - 上传失败: {str(e)}")
        return None

def cleanup_empty_dirs(path_to_clean):
    """递归清理指定路径下的空目录"""
    if not os.path.isdir(path_to_clean):
        return
    print(f"runpod-worker-comfy - Starting cleanup of empty directories in {path_to_clean}")
    # 从底层向上遍历，这样才能删除空的父目录
    for root, dirs, files in os.walk(path_to_clean, topdown=False):
        for name in dirs:
            try:
                dir_path = os.path.join(root, name)
                if not os.listdir(dir_path): # 检查目录是否为空
                    os.rmdir(dir_path)
                    print(f"runpod-worker-comfy - Removed empty directory: {dir_path}")
            except OSError as e:
                # 忽略删除失败（可能因为权限或目录非空）
                print(f"runpod-worker-comfy - Error removing directory {dir_path}: {e}")
    print(f"runpod-worker-comfy - Finished cleanup of empty directories.")

# --- 输入验证和服务器检查 ---
def validate_input(job_input):
    """
    验证输入数据的格式和内容

    Args:
        job_input: 输入数据，可以是字符串或字典

    Returns:
        tuple: (验证后的数据, 错误信息)
    """
    if job_input is None:
        return None, "Input is missing"

    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input string"

    if not isinstance(job_input, dict):
         return None, "Input must be a JSON object"

    workflow = job_input.get("workflow")
    if workflow is None:
        return None, "Missing 'workflow' key in input"
    if not isinstance(workflow, dict):
        return None, "'workflow' must be a JSON object"

    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list):
            return None, "'images' must be a list"
        for i, image_input in enumerate(images):
            if not isinstance(image_input, dict):
                return None, f"Item at index {i} in 'images' must be an object"
            if "name" not in image_input or "image" not in image_input:
                return None, f"Item at index {i} in 'images' must have 'name' and 'image' keys"
            if not isinstance(image_input["name"], str):
                return None, f"Image name at index {i} must be a string"
            if not isinstance(image_input["image"], str):
                return None, f"Image data at index {i} must be a string (base64 or URL)"

    # 可以添加更多针对workflow内容的验证（如果需要）

    return {"workflow": workflow, "images": images}, None

def check_server(url, retries=COMFY_API_AVAILABLE_MAX_RETRIES, delay=COMFY_API_AVAILABLE_INTERVAL_MS):
    """检查 ComfyUI 服务器是否可用"""
    print(f"runpod-worker-comfy - Checking ComfyUI API at {url}...")
    for i in range(retries):
        try:
            response = requests.get(url, timeout=2) # 设置短暂超时
            if response.status_code == 200:
                print(f"runpod-worker-comfy - ComfyUI API is reachable.")
                return True
        except requests.exceptions.RequestException:
            pass # 忽略连接错误，继续重试
        time.sleep(delay / 1000)
    print(f"runpod-worker-comfy - Failed to connect to ComfyUI API at {url} after {retries} attempts.")
    return False

# --- ComfyUI 交互 ---
def download_image(url):
    """从URL下载图片"""
    try:
        response = requests.get(url, timeout=20) # 增加下载超时时间
        response.raise_for_status()
        return response.content
    except requests.exceptions.RequestException as e:
        print(f"runpod-worker-comfy - Error downloading image from URL {url}: {str(e)}")
        return None

def upload_images(images):
    if not images:
        return {"status": "success", "message": "No images to upload.", "details": []}

    # 确保输入目录存在
    input_dir = "/workspace/ComfyUI/input"
    os.makedirs(input_dir, exist_ok=True)
    
    uploaded_files_info = []
    errors = []
    print(f"runpod-worker-comfy - Uploading {len(images)} image(s) to ComfyUI...")

    for image_input in images:
        name = image_input["name"]
        image_data_str = image_input["image"]
        blob = None

        # 确保文件名是安全的
        safe_filename = os.path.basename(name)
        # Construct the full path in the ComfyUI input directory
        local_path = os.path.join(input_dir, safe_filename)

        # Check if image_data_str is a URL
        if isinstance(image_data_str, str) and image_data_str.startswith(('http://', 'https://')):
            print(f"runpod-worker-comfy - Downloading image {name} from URL: {image_data_str[:100]}...") # Log truncated URL
            try:
                blob = download_image(image_data_str)
                if blob is None:
                    errors.append(f"Failed to download image '{name}' from URL.")
                    continue # Skip to the next image if download failed
            except Exception as e:
                errors.append(f"Error downloading image '{name}' from URL: {e}")
                continue
        elif isinstance(image_data_str, str):
             # Assume it's base64 if it's a string and not a URL
            print(f"runpod-worker-comfy - Decoding base64 for image {name}...")
            try:
                blob = base64.b64decode(image_data_str)
            except Exception as e:
                errors.append(f"Failed to decode base64 for image '{name}': {e}")
                continue # Skip to next image if decoding failed
        else:
            # Handle cases where image data is not a string (unexpected format)
            errors.append(f"Invalid image data format for image '{name}': Expected URL or base64 string.")
            continue

        # If blob was successfully obtained (downloaded or decoded)
        if blob:
            try:
                # 保存下载或解码后的图片到 ComfyUI 输入目录
                print(f"runpod-worker-comfy - Saving image '{name}' to {local_path}")
                with open(local_path, 'wb') as f:
                    f.write(blob)
                print(f"runpod-worker-comfy - Saved image to {local_path}")

                # 将本地文件上传到 ComfyUI API (保持现有逻辑)
                print(f"runpod-worker-comfy - Uploading saved image '{name}' via ComfyUI API...")
                # Make sure to open the *saved* local file for upload
                with open(local_path, 'rb') as f_upload:
                    files = {
                        "image": (safe_filename, f_upload, "image/png"), # Use safe_filename for upload
                        "overwrite": (None, "true"),
                    }
                    upload_url = f"http://{COMFY_HOST}/upload/image"
                    response = requests.post(upload_url, files=files, timeout=30) # Add timeout to upload

                if response.status_code == 200:
                    uploaded_info = response.json()
                    # Add the local path info for reference if needed, though ComfyUI response is primary
                    uploaded_info['local_path'] = local_path
                    uploaded_files_info.append(uploaded_info)
                    print(f"runpod-worker-comfy - Successfully uploaded '{name}' to ComfyUI.")
                else:
                    errors.append(f"Error uploading '{name}' to ComfyUI API: {response.status_code} - {response.text}")
                    # Attempt cleanup of local file if API upload fails?
                    # cleanup_local_file(local_path, f"failed upload image {name}")
            except Exception as e:
                errors.append(f"Error processing/saving/uploading '{name}': {e}")
                # Ensure cleanup if saving/uploading fails mid-way
                cleanup_local_file(local_path, f"error processing image {name}")
        # If blob is None (due to download/decode failure handled above), loop continues

    if errors:
        print(f"runpod-worker-comfy - Image upload(s) finished with errors.")
        return {
            "status": "error",
            "message": "Some images failed to upload.",
            "details": errors,
            "uploaded": uploaded_files_info # 也返回成功上传的信息
        }
    else:
        print(f"runpod-worker-comfy - All image(s) uploaded successfully to ComfyUI.")
        return {
            "status": "success",
            "message": "All images uploaded successfully.",
            "details": uploaded_files_info # 返回 ComfyUI 的文件信息
        }

def queue_workflow(workflow):
    """向 ComfyUI 提交工作流"""
    try:
        # 在提交工作流之前确保所有引用的图片文件存在
        input_dir = "/workspace/ComfyUI/input"
        for node_id, node_data in workflow.items():
            if isinstance(node_data, dict) and node_data.get("class_type") == "LoadImage":
                image_path = os.path.join(input_dir, node_data.get("inputs", {}).get("image", ""))
                if not os.path.exists(image_path):
                    print(f"Warning: Image file not found: {image_path}")
        
        # 使用 requests 提交工作流
        prompt_data = {"prompt": workflow}
        response = requests.post(
            f"http://{COMFY_HOST}/prompt",
            json=prompt_data,
            timeout=10
        )
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Failed to queue prompt, status code: {response.status_code}, message: {response.text}")
    except Exception as e:
        print(f"runpod-worker-comfy - Error queuing workflow: {e}")
        raise # 将异常重新抛出，以便上层处理

# --- 输出处理 ---
def cleanup_local_file(file_path, file_description="file"):
    """尝试清理本地文件并记录错误"""
    if file_path and os.path.exists(file_path):
        try:
            os.remove(file_path)
            print(f"runpod-worker-comfy - Removed local {file_description}: {file_path}")
        except OSError as e:
            print(f"runpod-worker-comfy - Error removing local {file_description} {file_path}: {e}")

def generate_video_thumbnail(video_path, time_offset="00:00:01.000"):
    """从视频生成缩略图"""
    thumbnail_path = None
    try:
        # 创建一个临时文件名
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp_file:
            thumbnail_path = tmp_file.name

        # 使用ffmpeg生成缩略图
        cmd = [
            'ffmpeg',
            '-hide_banner', # 减少日志输出
            '-loglevel', 'error', # 只输出错误
            '-i', video_path,
            '-ss', time_offset, # 精确到毫秒
            '-vframes', '1',    # 只取一帧
            '-vf', 'scale=320:-1', # 缩放宽度为320，高度自适应
            '-q:v', '3',        # JPEG 质量 (2-5 是一个好范围)
            '-y', thumbnail_path # 覆盖已存在的文件
        ]

        print(f"runpod-worker-comfy - Generating thumbnail for {video_path} at {thumbnail_path}")
        process = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(f"runpod-worker-comfy - Thumbnail generation successful for {video_path}")
        return thumbnail_path

    except FileNotFoundError:
        print("runpod-worker-comfy - Error generating thumbnail: ffmpeg command not found. Ensure ffmpeg is installed and in PATH.")
        cleanup_local_file(thumbnail_path, "thumbnail temp file") # 清理可能的空文件
        return None
    except subprocess.CalledProcessError as e:
        print(f"runpod-worker-comfy - Error generating thumbnail for {video_path}: ffmpeg failed.")
        print(f"ffmpeg stderr: {e.stderr}")
        cleanup_local_file(thumbnail_path, "thumbnail temp file")
        return None
    except Exception as e:
        print(f"runpod-worker-comfy - Unexpected error generating thumbnail for {video_path}: {str(e)}")
        cleanup_local_file(thumbnail_path, "thumbnail temp file")
        return None

def process_output_item(item_info, job_id):
    """
    处理单个 ComfyUI 输出项（图像、视频或 GIF）。

    Args:
        item_info (dict): ComfyUI 输出列表中的单个项目信息。
                          Expected keys: 'filename', 'subfolder', 'type' (e.g., 'output', 'temp').
                          'fullpath' might be present for videos/gifs.
        job_id (str): 当前作业的 ID，用于 B2 路径。

    Returns:
        tuple: (result_dict, error_str)
               result_dict: 包含 'url', 'thumbnail_url', 'type' 的字典，成功时返回。
               error_str: 描述错误的字符串，失败时返回。
               任一者为 None。
    """
    local_file_path = None
    thumbnail_path = None
    try:
        filename = item_info.get("filename")
        item_type_reported = item_info.get("type", "output") # Get type from ComfyUI history

        # --- Add check for temporary files ---
        # Skip processing if it looks like a temporary file based on name or type
        if not filename or "_temp_" in filename or item_type_reported == "temp":
            print(f"runpod-worker-comfy - Skipping likely temporary file: {filename} (type: {item_type_reported})")
            return None, None # Return None for both result and error to indicate skipped
        # --- End check ---

        if not filename:
            return None, f"Skipping item with missing filename: {item_info}"

        subfolder = item_info.get("subfolder", "")
        # 'fullpath' is more reliable for videos/gifs if present
        local_file_path = item_info.get("fullpath")

        if not local_file_path:
            # Construct path if fullpath is missing (common for images)
            relative_path = os.path.join(subfolder, filename)
            # Use the unified output path
            local_file_path = os.path.join(COMFYUI_OUTPUT_PATH, relative_path.lstrip('/'))

        if not os.path.exists(local_file_path):
            # Try the alternative base path just in case configuration is odd
            alt_path = os.path.join("/comfyui/output", relative_path.lstrip('/'))
            if os.path.exists(alt_path):
                local_file_path = alt_path
                print(f"runpod-worker-comfy - Info: Found file in alternative path: {alt_path}")
            else:
                 return None, f"Output file not found at expected paths: {local_file_path} or {alt_path}"

        file_ext = os.path.splitext(filename)[1].lower()
        is_gif = file_ext == '.gif'
        is_video = file_ext in SUPPORTED_VIDEO_FORMATS and not is_gif
        is_image = not is_video and not is_gif # Assume anything else is an image for now

        if is_gif:
            storage_dir = 'gifs'
            item_type = 'gif'
        elif is_video:
            storage_dir = 'videos'
            item_type = 'video'
        elif is_image:
            storage_dir = 'images'
            item_type = 'image'
        else:
             return None, f"Unsupported file type for output: {filename}"

        print(f"runpod-worker-comfy - Processing {item_type} output: {local_file_path}")

        # Upload the main file
        b2_file_path = f"{job_id}/{storage_dir}/{filename}"
        file_url = upload_to_b2(local_file_path, b2_file_path)

        if not file_url:
            # Don't clean up local file yet if upload failed, might be needed for retry/debug
            return None, f"Failed to upload {item_type} {filename} to B2."

        thumbnail_url = None
        if item_type == 'video': # Only generate thumbnails for videos (not gifs)
            print(f"runpod-worker-comfy - Generating thumbnail for video: {filename}")
            thumbnail_path = generate_video_thumbnail(local_file_path)
            if thumbnail_path:
                try:
                    thumb_filename = f"{os.path.splitext(filename)[0]}_thumb.jpg"
                    b2_thumbnail_path = f"{job_id}/thumbnails/{thumb_filename}"
                    thumbnail_url = upload_to_b2(thumbnail_path, b2_thumbnail_path)
                    if thumbnail_url:
                        print(f"runpod-worker-comfy - Successfully uploaded thumbnail to: {thumbnail_url}")
                    else:
                        # Non-fatal: Log error but continue processing main video
                        print(f"runpod-worker-comfy - Warning: Failed to upload thumbnail for {filename}")
                finally:
                    cleanup_local_file(thumbnail_path, "thumbnail")
            else:
                 print(f"runpod-worker-comfy - Warning: Failed to generate thumbnail for {filename}")

        # Main file uploaded successfully, now cleanup local file
        cleanup_local_file(local_file_path, item_type)

        result_data = {
            "url": file_url,
            "thumbnail_url": thumbnail_url, # Will be None if not applicable or failed
            "type": item_type
        }
        print(f"runpod-worker-comfy - Successfully processed {item_type} ({filename}) to: {file_url}")
        return result_data, None

    except Exception as e:
        error_msg = f"Error processing output item {item_info.get('filename', 'Unknown Filename')}: {str(e)}"
        print(f"runpod-worker-comfy - {error_msg}")
        # Attempt cleanup even on error
        cleanup_local_file(local_file_path, "output file on error")
        cleanup_local_file(thumbnail_path, "thumbnail on error")
        return None, error_msg


def process_comfyui_outputs(outputs, job_id):
    """
    处理来自 ComfyUI 的所有输出（图像、视频、GIF）。

    Args:
        outputs (dict): ComfyUI /history/<prompt_id> 响应中的 'outputs' 字典。
        job_id (str): 当前作业 ID。

    Returns:
        dict: 包含处理结果和状态的字典。
              Keys: 'status', 'message', 'results' (list of processed items), 'errors' (list of error strings)
    """
    use_b2 = bool(os.environ.get("BUCKET_ACCESS_KEY_ID", False))
    if not use_b2:
        print("runpod-worker-comfy - B2 storage is not configured for output.")
        return {"status": "error", "message": "B2 storage is not configured", "results": [], "errors": ["B2 storage is not configured."]}

    processed_results = []
    errors = []

    print(f"runpod-worker-comfy - Processing outputs for job {job_id}...")

    for node_id, node_output in outputs.items():
        output_items = []
        # Check for different possible output keys
        if "images" in node_output:
            output_items.extend(node_output["images"])
        if "videos" in node_output:
            output_items.extend(node_output["videos"])
        if "gifs" in node_output:
             output_items.extend(node_output["gifs"])
        # Add checks for other potential output keys if necessary

        if not output_items:
            continue

        print(f"runpod-worker-comfy - Found {len(output_items)} output item(s) in node {node_id}")

        for item_info in output_items:
            result_data, error_str = process_output_item(item_info, job_id)
            if error_str:
                errors.append(error_str)
            if result_data:
                processed_results.append(result_data)

    # Cleanup potentially empty directories after processing all items
    cleanup_empty_dirs(COMFYUI_OUTPUT_PATH)

    # Determine final status
    if not processed_results and not errors:
         print("runpod-worker-comfy - No processable outputs found in the workflow result.")
         return {"status": "warning", "message": "No processable outputs found.", "results": [], "errors": []}
    elif errors:
         status = "partial_success" if processed_results else "error"
         message = f"Processed outputs with {len(errors)} errors."
         print(f"runpod-worker-comfy - Finished processing outputs with errors. Status: {status}")
         return {"status": status, "message": message, "results": processed_results, "errors": errors}
    else:
        print(f"runpod-worker-comfy - Successfully processed {len(processed_results)} output item(s).")
        return {"status": "success", "message": "All outputs processed successfully.", "results": processed_results, "errors": []}


# --- Wait for Workflow Completion ---
def wait_for_workflow_completion(prompt_id, job_id):
    """轮询 ComfyUI 直到工作流完成、失败或超时。"""
    print(f"runpod-worker-comfy - Waiting for workflow completion (Prompt ID: {prompt_id})...")
    start_time = time.time()
    last_error = None
    outputs = {}

    while True:
        try:
            # 检查是否超时
            elapsed_time = time.time() - start_time
            if elapsed_time > JOB_TIMEOUT_SECONDS:
                print(f"runpod-worker-comfy - Job {job_id} timed out after {JOB_TIMEOUT_SECONDS} seconds (Prompt ID: {prompt_id})")
                return {"status": "error", "error": f"Job processing timed out after {JOB_TIMEOUT_SECONDS} seconds"}

            # 检查工作流历史
            history_url = f"http://{COMFY_HOST}/history/{prompt_id}"
            response = requests.get(history_url, timeout=5)

            if response.status_code == 200:
                history_data = response.json()
                if prompt_id in history_data:
                    workflow_data = history_data[prompt_id]
                    outputs = workflow_data.get("outputs", {})

                    # 检查工作流级别的错误
                    if "error" in workflow_data:
                         last_error = workflow_data["error"]
                         print(f"runpod-worker-comfy - Workflow error detected: {last_error}")

                    # 检查节点状态错误 (如果存在 status 字段)
                    if "status" in workflow_data and isinstance(workflow_data["status"], dict):
                        for node_id, node_data in workflow_data["status"].items():
                             # Check if node_data is a dictionary and has an 'error' key
                            if isinstance(node_data, dict) and "error" in node_data:
                                node_error = node_data['error']
                                print(f"runpod-worker-comfy - Node {node_id} error: {node_error}")
                                # Use the first node error encountered if no workflow-level error exists
                                if not last_error:
                                    last_error = f"Node {node_id}: {node_error}"


                    # 检查是否完成 (有输出) 或失败 (有错误)
                    if outputs:
                        print(f"runpod-worker-comfy - Workflow completed successfully (Prompt ID: {prompt_id})")
                        return {"status": "success", "outputs": outputs}
                    elif last_error:
                        print(f"runpod-worker-comfy - Workflow failed (Prompt ID: {prompt_id}): {last_error}")
                        return {
                            "status": "error",
                            "error": f"Workflow execution failed: {last_error}",
                            "detail": workflow_data # Optionally include full data for debugging
                        }
                    # else: still running, continue polling

            elif response.status_code == 404:
                # Prompt ID might not appear immediately, treat as still running for a while
                print(f"runpod-worker-comfy - Prompt ID {prompt_id} not found in history yet, continuing poll...")
            else:
                # Handle other unexpected HTTP statuses
                print(f"runpod-worker-comfy - Unexpected HTTP status {response.status_code} when checking history for {prompt_id}. Response: {response.text}")
                # Consider this a transient error and continue polling for a few retries? Or fail fast?
                # Let's continue polling for now.

            # Wait before next poll (ensure this happens even after exceptions)
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)

        except requests.exceptions.Timeout:
             print(f"runpod-worker-comfy - Timeout connecting to ComfyUI history endpoint for {prompt_id}. Retrying...")
             # Wait slightly longer on timeout before retrying
             time.sleep(max(COMFY_POLLING_INTERVAL_MS / 1000, 1.0))
        except requests.exceptions.RequestException as e:
            print(f"runpod-worker-comfy - Error checking workflow status for {prompt_id}: {str(e)}. Retrying...")
            # Wait before retrying on other request exceptions
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)

    # Remove the final block based on retries, as it should be unreachable
    # # If loop finishes without success or specific error
    # final_error_message = "Workflow did not complete successfully after maximum retries."
    # if last_error:
    #      final_error_message = f"Workflow failed after maximum retries: {last_error}"
    # print(f"runpod-worker-comfy - {final_error_message} (Prompt ID: {prompt_id})")
    # return {
    #     "status": "error",
    #     "error": final_error_message,
    #     "detail": "Maximum polling retries reached or final state indicates failure."
    # }


# --- 主处理函数 ---
def handler(job):
    """
    主处理函数，处理整个工作流程：
    1. 初始化 B2 (如果配置)
    2. 验证输入数据
    3. 检查 ComfyUI 服务可用性
    4. 上传输入图片（如果有）
    5. 提交工作流到 ComfyUI
    6. 等待处理完成
    7. 处理输出（图片或视频/GIF）
    8. 返回结果
    """

    # 在处理新作业之前尝试清理 VRAM 缓存
    try:
        print("runpod-worker-comfy - Cleaning VRAM cache before new job...")
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        print("runpod-worker-comfy - VRAM cache cleaning attempt finished.")
    except Exception as e:
        print(f"runpod-worker-comfy - Error during VRAM cache cleaning: {e}")
        # 不应阻止作业处理，只记录错误

    job_input = job.get("input", {})
    job_id = job.get("id", "unknown_job")
    print(f"runpod-worker-comfy - Received job: {job_id}")

    # 1. 初始化 B2 (如果需要)
    initialize_b2()

    try:
        # 2. 验证输入
        print("runpod-worker-comfy - Validating input...")
        validated_data, error_message = validate_input(job_input)
        if error_message:
            print(f"runpod-worker-comfy - Input validation failed: {error_message}")
            return {"error": f"Input validation failed: {error_message}"}
        print("runpod-worker-comfy - Input validation successful.")

        workflow = validated_data["workflow"]
        images_to_upload = validated_data.get("images")

        # 3. 确保ComfyUI API可用
        if not check_server(f"http://{COMFY_HOST}"):
            return {"error": "ComfyUI API is not available"}

        # 4. 上传输入图片（如果有）
        if images_to_upload:
            upload_result = upload_images(images_to_upload)
            if upload_result["status"] == "error":
                print(f"runpod-worker-comfy - Input image upload failed: {upload_result.get('message')}")
                return {"error": f"Input image upload failed: {upload_result.get('message')}", "details": upload_result.get("details")}

        # 5. 提交工作流
        print("runpod-worker-comfy - Queuing workflow...")
        try:
            queued_workflow = queue_workflow(workflow)
            prompt_id = queued_workflow.get("prompt_id")
            if not prompt_id:
                raise ValueError(f"ComfyUI did not return a prompt_id. Response: {queued_workflow}")
            print(f"runpod-worker-comfy - Workflow queued successfully with Prompt ID: {prompt_id}")
        except Exception as e:
            print(f"runpod-worker-comfy - Error queuing workflow: {str(e)}")
            return {"error": f"Error queuing workflow: {str(e)}"}

        # 6. 等待处理完成
        completion_result = wait_for_workflow_completion(prompt_id, job_id)

        if completion_result["status"] == "error":
             print(f"runpod-worker-comfy - Workflow completion check failed for job {job_id}: {completion_result.get('error')}")
             # Ensure the error response is structured correctly
             error_response = {
                 "error": completion_result.get('error', 'Unknown workflow completion error'),
                 "status": "error"
             }
             if "detail" in completion_result:
                 error_response["detail"] = completion_result["detail"]
             return error_response

        outputs = completion_result.get("outputs", {})
        if not outputs:
             # This case should ideally be caught by wait_for_workflow_completion, but as a fallback:
             print(f"runpod-worker-comfy - Workflow completed but no outputs dictionary found for job {job_id}.")
             return {"error": "Workflow finished but no outputs were found.", "status": "error"}


        # 7. 处理输出 (统一处理)
        print(f"runpod-worker-comfy - Processing ComfyUI outputs for job {job_id}...")
        output_processing_result = process_comfyui_outputs(outputs, job_id)

        # 构建最终返回结果
        final_result = {
            "status": output_processing_result.get("status", "error"), # Default to error if status missing
            "message": output_processing_result.get("message", "Output processing failed."),
            "outputs": output_processing_result.get("results", []), # Renamed 'results' to 'outputs' for clarity
            "processing_errors": output_processing_result.get("errors", []) # Keep track of specific errors
        }

        # 如果没有任何可处理的输出，但工作流本身成功了，提供原始输出
        if final_result["status"] == "warning" and final_result["message"] == "No processable outputs found.":
             final_result["raw_outputs"] = outputs

        # 8. 返回结果
        final_result["refresh_worker"] = REFRESH_WORKER
        print(f"runpod-worker-comfy - Job {job_id} finished with overall status: {final_result.get('status')}")
        return final_result

    except Exception as e:
        error_type = type(e).__name__
        # Log the full traceback for unexpected errors
        import traceback
        traceback_str = traceback.format_exc()
        print(f"runpod-worker-comfy - Unexpected error in handler for job {job_id}: {error_type} - {str(e)}\n{traceback_str}")
        return {"error": f"An unexpected error occurred: {error_type} - {str(e)}"}


# --- 启动 RunPod Serverless ---
if __name__ == "__main__":
    print("runpod-worker-comfy - Starting RunPod Serverless worker...")
    # 在启动时尝试初始化 B2
    initialize_b2()
    runpod.serverless.start({"handler": handler})