import runpod
import json
import time
import os
import requests
import base64
from io import BytesIO
from PIL import Image, ImageFilter
from b2sdk.v2 import B2Api, InMemoryAccountInfo, UploadMode
import hashlib
import subprocess
import tempfile
from pathlib import Path

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
IMAGE_FILTER_BLUR_RADIUS = int(os.environ.get("IMAGE_FILTER_BLUR_RADIUS", 8))
# 视频相关配置
VIDEO_OUTPUT_PATH = "/workspace/ComfyUI/output"  # 修改默认路径
IMAGE_OUTPUT_PATH = os.environ.get("IMAGE_OUTPUT_PATH", "/comfyui/output") # 明确图片输出路径
SUPPORTED_VIDEO_FORMATS = ['.mp4', '.webm', '.avi', '.gif'] # 添加 gif 支持
# Job timeout in seconds
JOB_TIMEOUT_SECONDS = 900 # 15 minutes

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
        local_path = os.path.join(input_dir, safe_filename)

        if image_data_str.startswith(('http://', 'https://')):
            print(f"runpod-worker-comfy - Downloading image {name} from URL...")
            blob = download_image(image_data_str)
        else:
            try:
                blob = base64.b64decode(image_data_str)
            except Exception as e:
                errors.append(f"Failed to decode base64 for image '{name}': {e}")
                continue

        if blob:
            try:
                # 直接保存到输入目录
                with open(local_path, 'wb') as f:
                    f.write(blob)
                print(f"runpod-worker-comfy - Saved image to {local_path}")
                
                # 上传到 ComfyUI
                files = {
                    "image": (name, open(local_path, 'rb'), "image/png"),
                    "overwrite": (None, "true"),
                }
                upload_url = f"http://{COMFY_HOST}/upload/image"
                response = requests.post(upload_url, files=files)
                
                if response.status_code == 200:
                    uploaded_files_info.append(response.json())
                    print(f"runpod-worker-comfy - Successfully uploaded '{name}' to ComfyUI.")
                else:
                    errors.append(f"Error uploading '{name}' to ComfyUI: {response.text}")
            except Exception as e:
                errors.append(f"Error processing '{name}': {e}")

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
def base64_encode(file_path):
    """将文件转换为 base64 字符串"""
    try:
        with open(file_path, "rb") as file:
            encoded_string = base64.b64encode(file.read()).decode("utf-8")
            return encoded_string
    except Exception as e:
        print(f"runpod-worker-comfy - Error encoding file {file_path} to base64: {e}")
        return None

def handle_output_error(file_path, error_msg, output_type):
    """通用的输出处理错误处理函数"""
    if file_path and os.path.exists(file_path):
        try:
            os.remove(file_path)
        except Exception as e:
            print(f"runpod-worker-comfy - Error removing file {file_path}: {e}")
    return {
        "status": "error",
        "message": error_msg,
        "type": output_type
    }

def process_output_images(outputs, job_id):
    """处理所有图片输出并返回URL列表"""
    use_b2 = bool(os.environ.get("BUCKET_ACCESS_KEY_ID", False))
    if not use_b2:
        print("runpod-worker-comfy - B2 storage is not configured for image output.")
        return {"status": "error", "message": "B2 storage is not configured", "results": []}

    uploaded_urls = []
    errors = []

    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image_info in node_output["images"]:
                filename = image_info.get("filename")
                if not filename:
                    print(f"runpod-worker-comfy - Skipping image with missing filename in node {node_id}")
                    continue

                subfolder = image_info.get("subfolder", "")
                relative_path = os.path.join(subfolder, filename)
                local_image_path = os.path.join(IMAGE_OUTPUT_PATH, relative_path.lstrip('/'))

                if os.path.exists(local_image_path):
                    try:
                        print(f"runpod-worker-comfy - Processing image output: {local_image_path}")
                        b2_file_path = f"{job_id}/images/{filename}"
                        image_url = upload_to_b2(local_image_path, b2_file_path)

                        if image_url:
                            uploaded_urls.append(image_url)
                            print(f"runpod-worker-comfy - Successfully uploaded image to: {image_url}")
                        else:
                            errors.append(f"Failed to upload image {filename} to B2.")

                        # Clean up local file after processing
                        try:
                            os.remove(local_image_path)
                            print(f"runpod-worker-comfy - Removed local image file: {local_image_path}")
                        except OSError as e:
                            print(f"runpod-worker-comfy - Error removing local image file {local_image_path}: {e}")

                    except Exception as e:
                        error_msg = f"Error processing image {filename}: {str(e)}"
                        print(f"runpod-worker-comfy - {error_msg}")
                        errors.append(error_msg)
                        # Attempt cleanup even on error
                        if os.path.exists(local_image_path):
                            try:
                                os.remove(local_image_path)
                            except OSError as rm_e:
                                print(f"runpod-worker-comfy - Error removing file {local_image_path} after error: {rm_e}")
                else:
                     print(f"runpod-worker-comfy - Image file not found locally: {local_image_path}")
                     errors.append(f"Image file not found: {filename}")


    # Cleanup potentially empty directories after processing all images
    cleanup_empty_dirs(IMAGE_OUTPUT_PATH)

    if not uploaded_urls and not errors:
         print("runpod-worker-comfy - No image outputs found in the workflow result.")
         return {"status": "warning", "message": "No image outputs found.", "results": []}
    elif errors:
         print(f"runpod-worker-comfy - Finished processing images with {len(errors)} errors.")
         # Return success even if some images failed, but include errors
         return {"status": "partial_success" if uploaded_urls else "error", "message": f"Processed images with {len(errors)} errors.", "results": uploaded_urls, "errors": errors}
    else:
        print(f"runpod-worker-comfy - Successfully processed {len(uploaded_urls)} image(s).")
        return {"status": "success", "message": "All images processed successfully.", "results": uploaded_urls}

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
        if thumbnail_path and os.path.exists(thumbnail_path): os.remove(thumbnail_path) # 清理可能的空文件
        return None
    except subprocess.CalledProcessError as e:
        print(f"runpod-worker-comfy - Error generating thumbnail for {video_path}: ffmpeg failed.")
        print(f"ffmpeg stderr: {e.stderr}")
        if thumbnail_path and os.path.exists(thumbnail_path): os.remove(thumbnail_path)
        return None
    except Exception as e:
        print(f"runpod-worker-comfy - Unexpected error generating thumbnail for {video_path}: {str(e)}")
        if thumbnail_path and os.path.exists(thumbnail_path): os.remove(thumbnail_path)
        return None

def process_video_output(outputs, job_id):
    """处理所有视频和GIF输出并返回包含URL和缩略图URL的字典列表"""
    use_b2 = bool(os.environ.get("BUCKET_ACCESS_KEY_ID", False))
    if not use_b2:
        print("runpod-worker-comfy - B2 storage is not configured for video/gif output.")
        return {"status": "error", "message": "B2 storage is not configured", "results": []}

    processed_results = []
    errors = []

    for node_id, node_output in outputs.items():
        items = []
        output_type = None
        if "videos" in node_output:
            items = node_output["videos"]
            output_type = "video"
        elif "gifs" in node_output:
            items = node_output["gifs"]
            output_type = "gif"
        else:
            continue

        print(f"runpod-worker-comfy - Processing {output_type} outputs from node {node_id}")

        for item_info in items:
            local_file_path = None # Initialize for potential error handling cleanup
            try:
                # Extract full path if available, otherwise construct from filename/subfolder
                local_file_path = item_info.get("fullpath")
                filename = item_info.get("filename")
                subfolder = item_info.get("subfolder", "")

                if not local_file_path and filename:
                    # Attempt to construct path if fullpath is missing (e.g., from older ComfyUI versions?)
                     relative_path = os.path.join(subfolder, filename)
                     local_file_path = os.path.join(VIDEO_OUTPUT_PATH, relative_path.lstrip('/')) # Assume video path
                     print(f"runpod-worker-comfy - Warning: 'fullpath' missing for {filename}, constructing path: {local_file_path}")


                if not local_file_path or not os.path.exists(local_file_path):
                    error_msg = f"File not found or path missing for item in node {node_id}: {item_info.get('filename', 'Unknown Filename')}"
                    print(f"runpod-worker-comfy - {error_msg}")
                    errors.append(error_msg)
                    continue

                filename = os.path.basename(local_file_path) # Ensure filename is from path
                file_ext = os.path.splitext(filename)[1].lower()
                storage_dir = 'gifs' if file_ext == '.gif' else 'videos'

                print(f"runpod-worker-comfy - Processing {storage_dir} output: {local_file_path}")

                # Upload video/gif file
                b2_file_path = f"{job_id}/{storage_dir}/{filename}"
                file_url = upload_to_b2(local_file_path, b2_file_path)

                thumbnail_url = None
                if file_url and storage_dir == 'videos': # Only generate thumbnails for videos
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
                                errors.append(f"Failed to upload thumbnail for {filename}")
                        finally:
                            if os.path.exists(thumbnail_path):
                                try:
                                    os.remove(thumbnail_path)
                                except OSError as e:
                                     print(f"runpod-worker-comfy - Error removing thumbnail file {thumbnail_path}: {e}")
                    else:
                        print(f"runpod-worker-comfy - Failed to generate thumbnail for {filename}")
                        errors.append(f"Failed to generate thumbnail for {filename}")


                # Clean up local file after processing
                if os.path.exists(local_file_path):
                    try:
                         os.remove(local_file_path)
                         print(f"runpod-worker-comfy - Removed local file: {local_file_path}")
                    except OSError as e:
                        print(f"runpod-worker-comfy - Error removing local file {local_file_path}: {e}")

                if file_url:
                    processed_results.append({
                        "url": file_url,
                        "thumbnail_url": thumbnail_url, # Will be None for GIFs or if thumbnail failed
                        "type": output_type
                    })
                    print(f"runpod-worker-comfy - Successfully uploaded {output_type} to: {file_url}")
                else:
                    errors.append(f"Failed to upload {output_type} {filename} to B2.")


            except Exception as e:
                error_msg = f"Error processing {output_type or 'item'} {item_info.get('filename', 'Unknown Filename')}: {str(e)}"
                print(f"runpod-worker-comfy - {error_msg}")
                errors.append(error_msg)
                 # Attempt cleanup even on error
                if local_file_path and os.path.exists(local_file_path):
                     try:
                         os.remove(local_file_path)
                     except OSError as rm_e:
                         print(f"runpod-worker-comfy - Error removing file {local_file_path} after error: {rm_e}")


    # Cleanup potentially empty directories after processing all items
    cleanup_empty_dirs(VIDEO_OUTPUT_PATH) # Ensure correct path is cleaned

    if not processed_results and not errors:
        print("runpod-worker-comfy - No video or gif outputs found in the workflow result.")
        return {"status": "warning", "message": "No video or gif outputs found.", "results": []}
    elif errors:
        print(f"runpod-worker-comfy - Finished processing videos/gifs with {len(errors)} errors.")
         # Return success even if some failed, but include errors
        return {"status": "partial_success" if processed_results else "error", "message": f"Processed videos/gifs with {len(errors)} errors.", "results": processed_results, "errors": errors}
    else:
        print(f"runpod-worker-comfy - Successfully processed {len(processed_results)} video/gif item(s).")
        return {"status": "success", "message": "All videos/gifs processed successfully.", "results": processed_results}

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


        # 7. 处理输出
        print(f"runpod-worker-comfy - Processing outputs for job {job_id}...")
        final_result = {}
        processing_errors = []

        # 检查输出类型 - More robust check
        has_video_output = any(key in node_output for node_output in outputs.values() for key in ["videos", "gifs"])
        has_image_output = any("images" in node_output for node_output in outputs.values())


        if has_video_output:
            print("runpod-worker-comfy - Processing video/gif output...")
            video_result = process_video_output(outputs, job_id)
            final_result['videos'] = video_result.get('results', [])
            if video_result['status'] != 'success':
                 final_result['video_status'] = video_result['status']
                 final_result['video_message'] = video_result.get('message')
                 if 'errors' in video_result:
                     processing_errors.extend(video_result['errors'])

        # Process images even if videos were processed (workflows might output both)
        if has_image_output:
            print("runpod-worker-comfy - Processing image output...")
            image_result = process_output_images(outputs, job_id)
            final_result['images'] = image_result.get('results', [])
            if image_result['status'] != 'success':
                final_result['image_status'] = image_result['status']
                final_result['image_message'] = image_result.get('message')
                if 'errors' in image_result:
                     processing_errors.extend(image_result['errors'])


        if not has_video_output and not has_image_output:
            print("runpod-worker-comfy - No recognizable image or video/gif outputs found in workflow result.")
            final_result = {
                "status": "warning",
                "message": "Workflow completed, but no standard outputs were found.",
                "raw_outputs": outputs # Provide raw output for debugging
            }
        else:
             # Determine overall status based on processing results
             if processing_errors:
                 final_result['status'] = 'partial_success' if (final_result.get('videos') or final_result.get('images')) else 'error'
                 final_result['message'] = f"Job completed with {len(processing_errors)} output processing errors."
                 final_result['processing_errors'] = processing_errors
             else:
                 final_result['status'] = 'success'
                 final_result['message'] = "Job completed successfully."


        # 8. 返回结果
        final_result["refresh_worker"] = REFRESH_WORKER
        print(f"runpod-worker-comfy - Job {job_id} finished with overall status: {final_result.get('status')}")
        return final_result

    except Exception as e:
        error_type = type(e).__name__
        print(f"runpod-worker-comfy - Unexpected error: {error_type} - {str(e)}")
        return {"error": f"An unexpected error occurred: {error_type} - {str(e)}"}


# --- 启动 RunPod Serverless ---
if __name__ == "__main__":
    print("runpod-worker-comfy - Starting RunPod Serverless worker...")
    # 在启动时尝试初始化 B2
    initialize_b2()
    runpod.serverless.start({"handler": handler})