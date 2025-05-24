import runpod
import json
import time
import os
import requests
import base64
import hashlib
from io import BytesIO
from PIL import Image, ImageFilter, ImageOps
from b2sdk.v2 import B2Api, InMemoryAccountInfo, UploadMode
import torch
import gc
import urllib3 # Added import

# Disable InsecureRequestWarning when verify=False is used with requests
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning) # Added to disable warnings

# --- Allowlist specific classes for torch.load (PyTorch >= 1.13+) ---
# ... (Allowlist code remains the same) ...

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
            response = requests.get(url, timeout=2, verify=False) # Added verify=False
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
        # 在这里为外部图片下载添加 verify=False
        response = requests.get(url, timeout=20, verify=False) 
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
                # --- 智能EXIF处理：保留方向信息，清除其他EXIF数据 ---
                print(f"runpod-worker-comfy - Processing image {name} with smart EXIF handling...")
                
                # 先用PIL打开图片
                img = Image.open(BytesIO(blob))
                
                # 应用EXIF方向信息到图片像素数据中，然后清除EXIF
                img = ImageOps.exif_transpose(img)  # 这会根据EXIF方向信息旋转图片
                
                # 确定文件格式
                _original_root, original_ext = os.path.splitext(name)
                original_ext = original_ext.lower()
                
                # 确定保存格式和content_type
                if original_ext == '.gif':
                    # 对于GIF，保持原始数据以保留动画
                    print(f"runpod-worker-comfy - Using original blob for GIF image {name} to preserve animation.")
                    processed_blob = blob
                    content_type = "image/gif"
                else:
                    # 对于其他格式，处理方向信息后重新保存（不含EXIF）
                    output_bytes_io = BytesIO()
                    
                    if original_ext in ['.jpg', '.jpeg']:
                        save_format = 'JPEG'
                        content_type = "image/jpeg"
                        # JPEG不支持透明度，转换RGBA到RGB
                        if img.mode == 'RGBA':
                            print(f"runpod-worker-comfy - Converting RGBA image {name} to RGB for JPEG format.")
                            img = img.convert('RGB')
                        img.save(output_bytes_io, format=save_format, quality=95)
                    elif original_ext == '.png':
                        save_format = 'PNG'
                        content_type = "image/png"
                        img.save(output_bytes_io, format=save_format)
                    else:
                        # 其他格式默认保存为PNG
                        save_format = 'PNG'
                        content_type = "image/png"
                        print(f"runpod-worker-comfy - Unknown format for {name}, saving as PNG.")
                        img.save(output_bytes_io, format=save_format)
                    
                    processed_blob = output_bytes_io.getvalue()
                    print(f"runpod-worker-comfy - Image {name} processed: orientation applied, EXIF removed, saved as {save_format}.")
                
                # 保存处理后的图片到本地
                print(f"runpod-worker-comfy - Saving processed image '{name}' to {local_path}...")
                with open(local_path, 'wb') as f:
                    f.write(processed_blob) 
                print(f"runpod-worker-comfy - Saved image to {local_path}")

                print(f"runpod-worker-comfy - Uploading saved image '{name}' via ComfyUI API...")
                with open(local_path, 'rb') as f_upload:
                    files = {
                        "image": (safe_filename, f_upload, content_type),
                        "overwrite": (None, "true"),
                    }
                    upload_url = f"http://{COMFY_HOST}/upload/image"
                    response = requests.post(upload_url, files=files, timeout=30)

                if response.status_code == 200:
                    uploaded_info = response.json()
                    uploaded_info['local_path'] = local_path
                    uploaded_files_info.append(uploaded_info)
                    print(f"runpod-worker-comfy - Successfully uploaded '{name}' (as {content_type}) to ComfyUI.")
                else:
                    errors.append(f"Error uploading '{name}' to ComfyUI API: {response.status_code} - {response.text}")
                    cleanup_local_file(local_path, f"failed ComfyUI API upload for image {name}")

            except Exception as e:
                import traceback
                tb_str = traceback.format_exc()
                error_msg = f"Error during image processing/saving for '{name}': {e}. Traceback: {tb_str}"
                print(f"runpod-worker-comfy - {error_msg}")
                errors.append(error_msg)
                cleanup_local_file(local_path, f"error processing image {name}")

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

def process_output_item(item_info, job_id, should_generate_blur, blur_radius, thumbnail_width, thumbnail_quality, thumbnail_format):
    """
    处理单个 ComfyUI 输出项（图像、视频或 GIF）。
    Args:
        item_info (dict): ComfyUI 输出列表中的单个项目信息。
        job_id (str): 当前作业的 ID，用于 B2 路径。
        should_generate_blur (bool): Whether to generate a blurred version of the output.
        blur_radius (float): The radius for the blurred version.
        thumbnail_width (int): The width for the thumbnail.
        thumbnail_quality (int): The quality for the thumbnail.
        thumbnail_format (str): The format for the thumbnail.
    Returns:
        tuple: (result_dict, error_str)
               result_dict: 包含 'url', 'type' 的字典，成功时返回。
               error_str: 描述错误的字符串，失败时返回。
               任一者为 None。
    """
    local_file_path = None
    local_blurred_file_path = None # Initialize for cleanup in broader scope
    local_thumbnail_path = None # For thumbnail cleanup
    try:
        filename = item_info.get("filename")
        item_type_reported = item_info.get("type", "output")

        if not filename or "_temp_" in filename or item_type_reported == "temp":
            print(f"runpod-worker-comfy - Skipping likely temporary file: {filename} (type: {item_type_reported})")
            return None, None

        subfolder = item_info.get("subfolder", "")
        local_file_path = item_info.get("fullpath")

        if not local_file_path:
            relative_path = os.path.join(subfolder, filename)
            local_file_path = os.path.join(COMFYUI_OUTPUT_PATH, relative_path.lstrip('/'))

        if not os.path.exists(local_file_path):
            alt_path = os.path.join("/comfyui/output", relative_path.lstrip('/'))
            if os.path.exists(alt_path):
                local_file_path = alt_path
                print(f"runpod-worker-comfy - Info: Found file in alternative path: {alt_path}")
            else:
                 return None, f"Output file not found at expected paths: {local_file_path} or {alt_path}"

        file_ext = os.path.splitext(filename)[1].lower()
        is_gif = file_ext == '.gif'
        is_video = file_ext in SUPPORTED_VIDEO_FORMATS and not is_gif
        is_image = not is_video and not is_gif

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

        # Upload the main file (original)
        b2_original_file_path = f"{job_id}/{storage_dir}/{filename}"
        original_file_url = upload_to_b2(local_file_path, b2_original_file_path)

        if not original_file_url:
            cleanup_local_file(local_file_path, item_type) # Cleanup original if its upload failed
            return None, f"Failed to upload original {item_type} {filename} to B2."

        result_data = {
            "url": original_file_url,
            "type": item_type
        }

        # --- Thumbnail generation logic (for images only) ---
        if item_type == 'image':
            print(f"runpod-worker-comfy - Generating thumbnail for {filename}")
            try:
                with Image.open(local_file_path) as img:
                    original_width, original_height = img.size
                    if original_width == 0 or original_height == 0:
                        raise ValueError("Image dimensions are zero.")

                    w_percent = (thumbnail_width / float(original_width))
                    h_size = int((float(original_height) * float(w_percent)))
                    if h_size <= 0: # Ensure height is positive
                        h_size = 1 

                    thumbnail_img = img.resize((thumbnail_width, h_size), Image.Resampling.LANCZOS)
                    
                    # Define thumbnail filename
                    base_filename, _ = os.path.splitext(filename)
                    thumbnail_filename = f"thumb_{base_filename}.{thumbnail_format}"
                    local_thumbnail_path = os.path.join(os.path.dirname(local_file_path), thumbnail_filename)
                    
                    # Save thumbnail locally
                    thumbnail_img.save(local_thumbnail_path, format=thumbnail_format.upper(), quality=thumbnail_quality)
                    print(f"runpod-worker-comfy - Saved local thumbnail to {local_thumbnail_path}")
                    
                    # Upload thumbnail to B2
                    b2_thumbnail_file_path = f"{job_id}/{storage_dir}/{thumbnail_filename}"
                    thumbnail_url = upload_to_b2(local_thumbnail_path, b2_thumbnail_file_path)
                    
                    if thumbnail_url:
                        result_data['thumbnail_url'] = thumbnail_url
                        print(f"runpod-worker-comfy - Successfully uploaded thumbnail ({thumbnail_filename}) to: {thumbnail_url}")
                    else:
                        print(f"runpod-worker-comfy - Failed to upload thumbnail ({thumbnail_filename}) to B2.")
                
            except Exception as thumb_err:
                print(f"runpod-worker-comfy - Error generating or uploading thumbnail for {filename}: {str(thumb_err)}")
            finally:
                # Cleanup local thumbnail file regardless of B2 upload success for this attempt
                if local_thumbnail_path and os.path.exists(local_thumbnail_path):
                    cleanup_local_file(local_thumbnail_path, "thumbnail")
        # --- Thumbnail logic ends ---

        # --- Blur logic starts --- 
        if item_type == 'image' and should_generate_blur and blur_radius > 0:
            print(f"runpod-worker-comfy - Generating blurred version for {filename} with radius {blur_radius}")
            try:
                img = Image.open(local_file_path)
                # Ensure image is in a mode that supports blur (e.g., RGB, RGBA)
                # Common modes: L (luminance), RGB, RGBA, CMYK, YCbCr, I (integer), F (float)
                if img.mode not in ['RGB', 'RGBA', 'L']:
                    # Attempt to convert to a suitable mode, prefer RGBA if alpha might be present
                    # or L if it was grayscale, otherwise RGB.
                    if img.mode == 'P': # Palette mode, often needs conversion
                        img = img.convert('RGBA')
                    elif 'A' in img.mode : # Check for modes like LA, PA etc.
                        img = img.convert('RGBA')
                    elif img.mode == 'L':
                        pass # Already grayscale, blur should work
                    else: # For others like CMYK, YCbCr, etc., convert to RGB
                        img = img.convert('RGB')
                    print(f"runpod-worker-comfy - Converted image {filename} from mode {img.info.get('original_mode', 'unknown')} to {img.mode} for blurring.")

                blurred_img = img.filter(ImageFilter.GaussianBlur(radius=float(blur_radius))) # Ensure radius is float
                
                # New logic for blurred_filename using MD5 hash
                _dummy_base, ext = os.path.splitext(filename) # Get the original extension
                # filename variable already holds the original base filename (e.g., "Undressly_0001.jpg")
                hashed_filename_part = hashlib.md5(filename.encode('utf-8')).hexdigest()
                blurred_filename = hashed_filename_part + ext
                
                # Save blurred image next to the original, or use tempfile for more robust temp file handling
                local_blurred_file_path = os.path.join(os.path.dirname(local_file_path), blurred_filename)
                
                save_format = None
                original_ext_lower = ext.lower()
                if original_ext_lower in ['.jpg', '.jpeg']:
                    save_format = 'JPEG'
                elif original_ext_lower == '.png':
                    save_format = 'PNG'
                
                if save_format == 'JPEG' and blurred_img.mode == 'RGBA':
                    blurred_img = blurred_img.convert('RGB')

                blurred_img.save(local_blurred_file_path, format=save_format)
                print(f"runpod-worker-comfy - Saved local blurred image to {local_blurred_file_path}")
                
                b2_blurred_file_path = f"{job_id}/{storage_dir}/{blurred_filename}"
                blurred_file_url = upload_to_b2(local_blurred_file_path, b2_blurred_file_path)
                
                if blurred_file_url:
                    result_data['blurred_url'] = blurred_file_url
                    print(f"runpod-worker-comfy - Successfully uploaded blurred image ({blurred_filename}) to: {blurred_file_url}")
                else:
                    print(f"runpod-worker-comfy - Failed to upload blurred image ({blurred_filename}) to B2.")
                
                # Cleanup local blurred file regardless of B2 upload success for this attempt
                cleanup_local_file(local_blurred_file_path, "blurred " + item_type)

            except Exception as blur_err:
                print(f"runpod-worker-comfy - Error generating or uploading blurred version for {filename}: {str(blur_err)}")
                # If local_blurred_file_path was set and exists, try to clean it up
                if local_blurred_file_path and os.path.exists(local_blurred_file_path):
                    cleanup_local_file(local_blurred_file_path, "failed blurred " + item_type)
        # --- Blur logic ends ---

        # Main file (original) uploaded successfully. Cleanup the original local file.
        cleanup_local_file(local_file_path, item_type)

        print(f"runpod-worker-comfy - Successfully processed original {item_type} ({filename}) to: {original_file_url}")
        return result_data, None

    except Exception as e:
        error_msg = f"Error processing output item {item_info.get('filename', 'Unknown Filename')}: {str(e)}"
        print(f"runpod-worker-comfy - {error_msg}")
        cleanup_local_file(local_file_path, "output file on error")
        if local_blurred_file_path and os.path.exists(local_blurred_file_path): # Also cleanup blurred if it exists on main error
             cleanup_local_file(local_blurred_file_path, "blurred output file on error")
        if local_thumbnail_path and os.path.exists(local_thumbnail_path): # Also cleanup thumbnail if it exists on main error
            cleanup_local_file(local_thumbnail_path, "thumbnail file on error")
        return None, error_msg

def process_comfyui_outputs(outputs, job_id, should_generate_blur, blur_radius, thumbnail_width, thumbnail_quality, thumbnail_format):
    """
    处理来自 ComfyUI 的所有输出（图像、视频、GIF）。

    Args:
        outputs (dict): ComfyUI /history/<prompt_id> 响应中的 'outputs' 字典。
        job_id (str): 当前作业 ID。
        should_generate_blur (bool): Whether to generate a blurred version of the output.
        blur_radius (float): The radius for the blurred version.
        thumbnail_width (int): The width for the thumbnail.
        thumbnail_quality (int): The quality for the thumbnail.
        thumbnail_format (str): The format for the thumbnail.

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
            result_data, error_str = process_output_item(item_info, job_id, should_generate_blur, blur_radius, thumbnail_width, thumbnail_quality, thumbnail_format)
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
    outputs = {}

    while True:
        try:
            elapsed_time = time.time() - start_time
            if elapsed_time > JOB_TIMEOUT_SECONDS:
                print(f"runpod-worker-comfy - Job {job_id} timed out after {JOB_TIMEOUT_SECONDS} seconds (Prompt ID: {prompt_id})")
                return {"status": "error", "error": f"Job processing timed out after {JOB_TIMEOUT_SECONDS} seconds"}

            history_url = f"http://{COMFY_HOST}/history/{prompt_id}"
            response = requests.get(history_url, timeout=5)

            if response.status_code == 200:
                history_data = response.json()
                if prompt_id in history_data:
                    workflow_data = history_data[prompt_id]
                    prompt_status_obj = workflow_data.get("status", {})
                    current_outputs = workflow_data.get("outputs", {}) # Get current outputs
                    # Update main outputs dict only if new outputs are found, to preserve last known outputs on error
                    if current_outputs: 
                        outputs = current_outputs
                    
                    last_error_message = None

                    if prompt_status_obj.get("status_str") == "error":
                        messages = prompt_status_obj.get("messages", [])
                        for msg_list in messages: # messages is a list of lists/tuples
                            if isinstance(msg_list, (list, tuple)) and len(msg_list) > 1:
                                msg_type = msg_list[0]
                                msg_data = msg_list[1]
                                if msg_type == "execution_error" and isinstance(msg_data, dict):
                                    node_type = msg_data.get('node_type', 'UnknownNode')
                                    node_id_err = msg_data.get('node_id', 'N/A')
                                    exc_type = msg_data.get('exception_type', 'Error')
                                    exc_msg = msg_data.get('exception_message', 'Unknown error')
                                    # Traceback might be useful but can be very long
                                    # exc_traceback = msg_data.get('traceback', '') 
                                    last_error_message = f"Node {node_type} (ID: {node_id_err}): {exc_type}: {exc_msg}"
                                    break 
                        if not last_error_message:
                            last_error_message = "Workflow status reported as 'error' by ComfyUI with no detailed message in status.messages."
                        print(f"runpod-worker-comfy - ComfyUI reported workflow error. Status: {prompt_status_obj.get('status_str')}, Details: {last_error_message}")

                    if not last_error_message and isinstance(outputs, dict):
                        for node_id_out, node_output_data in outputs.items():
                            if isinstance(node_output_data, dict) and "errors" in node_output_data and node_output_data["errors"]:
                                try:
                                    error_detail = node_output_data["errors"][0] 
                                    err_type = error_detail.get('type', node_id_out) 
                                    err_msg = error_detail.get('message', 'Unknown error in node output')
                                    err_details = error_detail.get('details', '')
                                    last_error_message = f"Node output error ({err_type} for node {node_id_out}): {err_msg}. Details: {err_details}"
                                    print(f"runpod-worker-comfy - Error detected in node output '{node_id_out}': {last_error_message}")
                                except Exception as e_parse:
                                    last_error_message = f"Error detected in node output '{node_id_out}', but failed to parse details: {str(node_output_data['errors'])}. Parse error: {e_parse}"
                                    print(f"runpod-worker-comfy - {last_error_message}")
                                break 
                    
                    is_completed = prompt_status_obj.get("completed", False)

                    if last_error_message:
                        print(f"runpod-worker-comfy - Workflow failed (Prompt ID: {prompt_id}): {last_error_message}")
                        return {
                            "status": "error",
                            "error": f"Workflow execution failed: {last_error_message}",
                            "detail": workflow_data 
                        }

                    if is_completed:
                        if prompt_status_obj.get("status_str") == "success":
                            print(f"runpod-worker-comfy - Workflow completed successfully (Prompt ID: {prompt_id})")
                            return {"status": "success", "outputs": outputs}
                        else:
                            final_status_str = prompt_status_obj.get('status_str', 'unknown')
                            unhandled_error_message = f"Workflow completed with unhandled status '{final_status_str}' and no specific error messages captured. Outputs: {bool(outputs)}"
                            print(f"runpod-worker-comfy - {unhandled_error_message} (Prompt ID: {prompt_id})")
                            return {
                                "status": "error",
                                "error": unhandled_error_message,
                                "detail": workflow_data
                            }

            elif response.status_code == 404:
                print(f"runpod-worker-comfy - Prompt ID {prompt_id} not found in history yet, continuing poll...")
            else:
                print(f"runpod-worker-comfy - Unexpected HTTP status {response.status_code} when checking history for {prompt_id}. Response: {response.text}")

            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)

        except requests.exceptions.Timeout:
             print(f"runpod-worker-comfy - Timeout connecting to ComfyUI history endpoint for {prompt_id}. Retrying...")
             time.sleep(max(COMFY_POLLING_INTERVAL_MS / 1000, 1.0))
        except requests.exceptions.RequestException as e:
            print(f"runpod-worker-comfy - Error checking workflow status for {prompt_id}: {str(e)}. Retrying...")
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
        except json.JSONDecodeError as e:
            print(f"runpod-worker-comfy - Error decoding JSON from history for {prompt_id}: {str(e)}. Response: {response.text if 'response' in locals() else 'N/A'}. Retrying...")
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)


# --- 主处理函数 ---
def handler(job):
    """
    RunPod Handler function
    """
    job_id = job.get('id', 'unknown_job')
    print(f"runpod-worker-comfy - Job {job_id} received.")

    # 记录开始时间
    start_time = time.time()

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

    # job_input is the raw input from RunPod, which should be a dict if JSON was sent
    job_input_payload = job.get("input", {})
    print(f"runpod-worker-comfy - Received job input payload for job: {job_id}")

    # Get blur generation flag and custom radius from the job input payload
    should_generate_blur = job_input_payload.get("generate_blurred_image", True) # Default to True
    print(f"runpod-worker-comfy - Parsed 'should_generate_blur': {should_generate_blur} (Type: {type(should_generate_blur)})") # DEBUG LOG
    # Use API provided blur_radius if present and valid, otherwise default to ENV
    custom_blur_radius = job_input_payload.get("blur_radius")
    blur_radius_to_use = IMAGE_FILTER_BLUR_RADIUS # Default from ENV
    if isinstance(custom_blur_radius, (int, float)) and custom_blur_radius > 0:
        blur_radius_to_use = custom_blur_radius
        print(f"runpod-worker-comfy - Using custom blur radius from API: {blur_radius_to_use}")
    else:
        print(f"runpod-worker-comfy - Using default blur radius from ENV: {blur_radius_to_use}")

    # Thumbnail parameters
    thumb_width_param = job_input_payload.get("thumbnail_width", 256)
    thumb_quality_param = job_input_payload.get("thumbnail_quality", 75)
    thumb_format_param = job_input_payload.get("thumbnail_format", "webp").lower()

    # Validate thumbnail parameters
    try:
        thumbnail_width = int(thumb_width_param)
        if thumbnail_width <= 0:
            thumbnail_width = 256 # Default if invalid
            print(f"runpod-worker-comfy - Invalid thumbnail_width, using default {thumbnail_width}")
    except ValueError:
        thumbnail_width = 256
        print(f"runpod-worker-comfy - thumbnail_width not an int, using default {thumbnail_width}")

    try:
        thumbnail_quality = int(thumb_quality_param)
        if not (1 <= thumbnail_quality <= 100):
            thumbnail_quality = 75 # Default if out of range
            print(f"runpod-worker-comfy - Invalid thumbnail_quality, using default {thumbnail_quality}")
    except ValueError:
        thumbnail_quality = 75
        print(f"runpod-worker-comfy - thumbnail_quality not an int, using default {thumbnail_quality}")

    valid_formats = ["webp", "jpeg", "png"]
    if thumb_format_param not in valid_formats:
        thumbnail_format = "webp" # Default if invalid
        print(f"runpod-worker-comfy - Invalid thumbnail_format '{thumb_format_param}', using default {thumbnail_format}")
    else:
        thumbnail_format = thumb_format_param
    
    print(f"runpod-worker-comfy - Using thumbnail params: width={thumbnail_width}, quality={thumbnail_quality}, format={thumbnail_format}")

    # 1. 初始化 B2 (如果需要)
    initialize_b2()

    try:
        # 2. 验证输入
        print("runpod-worker-comfy - Validating input...")
        validated_data, error_message = validate_input(job_input_payload)
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
        output_processing_result = process_comfyui_outputs(outputs, job_id, should_generate_blur, blur_radius_to_use, thumbnail_width, thumbnail_quality, thumbnail_format)

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