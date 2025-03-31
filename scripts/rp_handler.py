import runpod
import json
import urllib.request
import urllib.parse
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
        error_msg = "B2 Bucket 未初始化，请检查以下配置："
        env_vars = {
            'BUCKET_ACCESS_KEY_ID': os.environ.get('BUCKET_ACCESS_KEY_ID', '未设置'),
            'BUCKET_SECRET_ACCESS_KEY': '已设置' if os.environ.get('BUCKET_SECRET_ACCESS_KEY') else '未设置',
            'BUCKET_NAME': os.environ.get('BUCKET_NAME', '未设置'),
            'BUCKET_ENDPOINT_URL': os.environ.get('BUCKET_ENDPOINT_URL', '未设置')
        }
        print(f"runpod-worker-comfy - {error_msg}")
        print("环境变量状态：")
        for key, value in env_vars.items():
            print(f"- {key}: {value}")
        return None

    try:
        endpoint_url = os.environ.get("BUCKET_ENDPOINT_URL", '')
        bucket_name = os.environ.get('BUCKET_NAME')
        
        if not endpoint_url or not bucket_name:
            error_msg = f"缺少必要的 B2 配置：\nBUCKET_ENDPOINT_URL: {endpoint_url}\nBUCKET_NAME: {bucket_name}"
            print(f"runpod-worker-comfy - {error_msg}")
            return None

        print(f"runpod-worker-comfy - 正在上传文件：")
        print(f"- 本地路径: {local_file_path}")
        print(f"- B2路径: {file_name}")
        print(f"- 文件大小: {os.path.getsize(local_file_path) / (1024*1024):.2f} MB")
        
        # 检查文件是否存在且可读
        if not os.path.exists(local_file_path):
            error_msg = f"本地文件不存在：{local_file_path}"
            print(f"runpod-worker-comfy - {error_msg}")
            return None
            
        if not os.access(local_file_path, os.R_OK):
            error_msg = f"文件无读取权限：{local_file_path}"
            print(f"runpod-worker-comfy - {error_msg}")
            return None

        # 检查文件是否为空
        if os.path.getsize(local_file_path) == 0:
            error_msg = f"文件大小为0：{local_file_path}"
            print(f"runpod-worker-comfy - {error_msg}")
            return None

        # 使用标准上传模式
        print("runpod-worker-comfy - 开始上传到 B2...")
        uploaded_file = b2_bucket_instance.upload_local_file(
            local_file=local_file_path,
            file_name=file_name
        )

        download_url = f"{endpoint_url}/{bucket_name}/{file_name}"
        print(f"runpod-worker-comfy - 上传成功：{download_url}")
        return download_url

    except Exception as e:
        error_msg = f"上传 {file_name} 到 B2 时出错: {str(e)}"
        print(f"runpod-worker-comfy - {error_msg}")
        # 打印更详细的错误信息
        import traceback
        print(f"runpod-worker-comfy - 详细错误信息：\n{traceback.format_exc()}")
        
        # 检查网络连接
        try:
            response = requests.get(endpoint_url, timeout=5)
            print(f"runpod-worker-comfy - B2 端点连接测试：HTTP {response.status_code}")
        except Exception as conn_err:
            print(f"runpod-worker-comfy - B2 端点连接失败：{str(conn_err)}")
        
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
        
        # 继续原有的提交逻辑
        prompt_data = {"prompt": workflow}
        data = json.dumps(prompt_data).encode('utf-8')
        req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.getcode() == 200:
                return json.loads(response.read())
            else:
                raise Exception(f"Failed to queue prompt, status code: {response.getcode()}, message: {response.read().decode()}")
    except Exception as e:
        print(f"runpod-worker-comfy - Error queuing workflow: {e}")
        raise # 将异常重新抛出，以便上层处理

def get_history(prompt_id):
    """获取指定 prompt_id 的处理历史"""
    try:
        with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}", timeout=5) as response:
             if response.getcode() == 200:
                 return json.loads(response.read())
             else:
                 # 可能历史还没准备好，返回空字典而不是抛异常
                 print(f"runpod-worker-comfy - Warning: Failed to get history for {prompt_id}, status: {response.getcode()}")
                 return {}
    except Exception as e:
        # 网络错误等也返回空字典
        print(f"runpod-worker-comfy - Error getting history for {prompt_id}: {e}")
        return {}

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

def process_output_images(outputs, job_id):
    """处理所有图片输出"""
    processed_images = []
    use_b2 = bool(os.environ.get("BUCKET_ACCESS_KEY_ID", False))

    print(f"runpod-worker-comfy - Processing image outputs for job {job_id}...")

    found_images = False
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            found_images = True
            for image_info in node_output["images"]:
                # ComfyUI 可能返回不带子文件夹的路径，进行兼容处理
                subfolder = image_info.get("subfolder", "")
                filename = image_info.get("filename")
                if not filename:
                    print(f"runpod-worker-comfy - Warning: Found image output in node {node_id} without filename.")
                    continue

                relative_path = os.path.join(subfolder, filename)
                local_image_path = os.path.join(IMAGE_OUTPUT_PATH, relative_path.lstrip('/'))
                print(f"runpod-worker-comfy - Found image output: {local_image_path}")

                if os.path.exists(local_image_path):
                    image_result = {"filename": filename} # 包含原始文件名
                    original_filename = os.path.basename(local_image_path)
                    blur_image_url = None

                    if use_b2:
                        # 处理模糊版本
                        local_blur_image_path = None
                        try:
                            filename_base, ext = os.path.splitext(original_filename)
                            # 使用 job_id 和原始文件名哈希生成唯一模糊文件名
                            blur_filename_base = hashlib.md5(f"{job_id}-{original_filename}".encode()).hexdigest()
                            blur_filename = f"{blur_filename_base}{ext}"
                            # 将模糊图创建在临时目录，避免权限问题
                            temp_dir = tempfile.gettempdir()
                            local_blur_image_path = os.path.join(temp_dir, blur_filename)

                            print(f"runpod-worker-comfy - Generating blurred version for {original_filename} at {local_blur_image_path}")
                            with Image.open(local_image_path) as img:
                                blurred = img.filter(ImageFilter.GaussianBlur(radius=IMAGE_FILTER_BLUR_RADIUS))
                                blurred.save(local_blur_image_path)

                            # 上传模糊版本到 B2
                            b2_blur_path = f"{job_id}/blurred/{blur_filename}"
                            blur_image_url = upload_to_b2(local_blur_image_path, b2_blur_path)
                            if blur_image_url:
                                image_result["blur_url"] = blur_image_url
                                print(f"runpod-worker-comfy - Blurred image uploaded to B2: {blur_image_url}")
                            else:
                                image_result["blur_error"] = "Failed to upload blurred image"

                        except Exception as e:
                            print(f"runpod-worker-comfy - Error processing blurred image for {original_filename}: {str(e)}")
                            image_result["blur_error"] = str(e)
                        finally:
                            # 清理本地模糊临时文件
                            if local_blur_image_path and os.path.exists(local_blur_image_path):
                                try:
                                    os.remove(local_blur_image_path)
                                    print(f"runpod-worker-comfy - Cleaned up temporary blurred image: {local_blur_image_path}")
                                except OSError as e:
                                     print(f"runpod-worker-comfy - Error cleaning up temp blur image {local_blur_image_path}: {e}")


                        # 上传原始图片到 B2 (模糊处理后上传原图)
                        b2_file_path = f"{job_id}/images/{original_filename}"
                        image_url = upload_to_b2(local_image_path, b2_file_path)
                        if image_url:
                            image_result["url"] = image_url
                            print(f"runpod-worker-comfy - Original image uploaded to B2: {image_url}")
                        else:
                            image_result["error"] = "Failed to upload original image to B2"

                    else:
                        # base64 image
                        encoded_image = base64_encode(local_image_path)
                        if encoded_image:
                             image_result["base64"] = encoded_image
                             print(f"runpod-worker-comfy - Image {original_filename} generated and converted to base64")
                        else:
                             image_result["error"] = "Failed to encode image to base64"

                    processed_images.append(image_result)

                    # 清理 ComfyUI 输出的原图 (无论成功与否都尝试清理)
                    try:
                        if os.path.exists(local_image_path):
                            os.remove(local_image_path)
                            print(f"runpod-worker-comfy - Cleaned up original image from ComfyUI output: {local_image_path}")
                    except Exception as e:
                        print(f"runpod-worker-comfy - Error cleaning up image {local_image_path}: {str(e)}")

                else:
                    print(f"runpod-worker-comfy - Image file does not exist: {local_image_path}")
                    processed_images.append({"filename": filename, "error": f"Output image file not found"})

    if not found_images:
         print("runpod-worker-comfy - No 'images' key found in any node output.")
         # 根据需求决定是否返回错误
         # return {"status": "warning", "message": "No image outputs found in the workflow result."}

    # 清理可能的空目录
    cleanup_empty_dirs(IMAGE_OUTPUT_PATH)

    if not processed_images:
         return {"status": "error", "message": "No image outputs were found or successfully processed."}

    return {"status": "success", "images": processed_images}

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
    """处理所有视频输出"""
    processed_videos = []
    use_b2 = bool(os.environ.get("BUCKET_ACCESS_KEY_ID", False))
    if not use_b2:
        print("runpod-worker-comfy - B2 is not configured. Cannot process video output.")
        return {"status": "error", "message": "B2 storage is not configured for video output."}

    print(f"runpod-worker-comfy - Processing video outputs for job {job_id}...")

    for node_id, node_output in outputs.items():
        # 检查输出类型
        if "videos" in node_output:
            output_type = "videos"
            items = node_output["videos"]
        elif "gifs" in node_output:
            output_type = "gifs"
            items = node_output["gifs"]
        else:
            continue

        for video_info in items:
            try:
                local_video_path = video_info.get("fullpath")
                if not local_video_path or not os.path.exists(local_video_path):
                    print(f"runpod-worker-comfy - Video file not found: {local_video_path}")
                    processed_videos.append({
                        "filename": video_info.get("filename"),
                        "error": "File not found"
                    })
                    continue

                filename = video_info.get("filename")
                # 根据文件扩展名决定目录
                file_ext = os.path.splitext(filename)[1].lower()
                if file_ext == '.gif':
                    output_dir = 'gifs'
                else:
                    output_dir = 'videos'

                print(f"runpod-worker-comfy - Processing {output_dir} file: {filename}")

                # 上传到对应目录
                b2_file_path = f"{job_id}/{output_dir}/{filename}"
                video_url = upload_to_b2(local_video_path, b2_file_path)
                
                if video_url:
                    video_result = {
                        "filename": filename,
                        "url": video_url,
                        "frame_rate": video_info.get("frame_rate"),
                        "format": video_info.get("format"),
                        "type": output_dir  # 添加类型信息
                    }
                    
                    # 只为视频文件生成缩略图，GIF 不需要
                    if output_dir == 'videos':
                        thumbnail_path = generate_video_thumbnail(local_video_path)
                        if thumbnail_path:
                            try:
                                thumb_filename = f"{os.path.splitext(filename)[0]}_thumb.jpg"
                                b2_thumbnail_path = f"{job_id}/thumbnails/{thumb_filename}"
                                thumbnail_url = upload_to_b2(thumbnail_path, b2_thumbnail_path)
                                if thumbnail_url:
                                    video_result["thumbnail_url"] = thumbnail_url
                            finally:
                                if os.path.exists(thumbnail_path):
                                    os.remove(thumbnail_path)
                    
                    processed_videos.append(video_result)
                    print(f"runpod-worker-comfy - Successfully processed {output_dir} file: {filename}")
                else:
                    processed_videos.append({
                        "filename": filename,
                        "error": f"Failed to upload to B2"
                    })

            except Exception as e:
                print(f"runpod-worker-comfy - Error processing file: {str(e)}")
                processed_videos.append({
                    "filename": video_info.get("filename"),
                    "error": f"Processing error: {str(e)}"
                })
            finally:
                # 清理原始文件
                try:
                    if os.path.exists(local_video_path):
                        os.remove(local_video_path)
                        print(f"runpod-worker-comfy - Cleaned up file: {local_video_path}")
                except Exception as e:
                    print(f"runpod-worker-comfy - Error cleaning up file: {e}")

    # 清理空目录
    cleanup_empty_dirs(VIDEO_OUTPUT_PATH)

    if not processed_videos:
        return {
            "status": "error",
            "message": "No outputs were successfully processed.",
            "type": "video"
        }

    return {
        "status": "success",
        "videos": processed_videos,
        "type": "video"
    }

def get_progress(prompt_id):
    """获取工作流处理的实时进度"""
    try:
        # 使用 requests 库，因为它处理 JSON 更方便，并能设置超时
        response = requests.get(f"http://{COMFY_HOST}/prompt/status/{prompt_id}", timeout=2)
        
        # 处理不同的状态码
        if response.status_code == 200:
            data = response.json()
            status_info = data.get("status", {})
            executing_node = status_info.get("executing")

            if executing_node:
                node_id = executing_node.get("node")
                progress = executing_node.get("progress", 0)
                return {
                    "status": "processing",
                    "progress": int(progress * 100) if progress is not None else 0,
                    "detail": f"Executing node {node_id}"
                }
            elif status_info.get("completed") is True:
                return {
                    "status": "completed",
                    "progress": 100,
                    "detail": "Workflow completed"
                }
            else:
                return {
                    "status": "pending",
                    "progress": 0,
                    "detail": "Waiting in queue or starting"
                }
        elif response.status_code == 404:
            # 如果是 404，检查历史记录
            history = get_history(prompt_id)
            if prompt_id in history:
                return {
                    "status": "completed",
                    "progress": 100,
                    "detail": "Workflow completed (found in history)"
                }
            return {
                "status": "pending",
                "progress": 0,
                "detail": "Prompt not found in active queue"
            }
        else:
            print(f"runpod-worker-comfy - Warning: Failed to get progress for {prompt_id}, status: {response.status_code}")
            return {
                "status": "unknown",
                "progress": 0,
                "detail": f"Failed to get status (HTTP {response.status_code})"
            }

    except requests.exceptions.RequestException as e:
        print(f"runpod-worker-comfy - Error getting progress for {prompt_id}: {e}")
        return {
            "status": "error",
            "progress": 0,
            "detail": f"Network error: {str(e)}"
        }
    except Exception as e:
        print(f"runpod-worker-comfy - Unexpected error getting progress for {prompt_id}: {e}")
        return {
            "status": "error",
            "progress": 0,
            "detail": f"Unexpected error: {str(e)}"
        }

# --- 主处理函数 ---
def handler(job):
    """
    主处理函数，处理整个工作流程：
    1. 初始化 B2 (如果配置)
    2. 验证输入数据
    3. 检查 ComfyUI 服务可用性
    4. 上传输入图片（如果有）
    5. 提交工作流到 ComfyUI
    6. 等待处理完成并监控进度
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

        # 等待处理完成并监控进度
        print(f"runpod-worker-comfy - Waiting for workflow completion (Prompt ID: {prompt_id})...")
        retries = 0
        last_progress_sent = None
        start_time = time.time()
        consecutive_404_count = 0  # 添加连续404计数器

        while retries < COMFY_POLLING_MAX_RETRIES:
            current_time = time.time()
            elapsed_time = current_time - start_time

            if elapsed_time > 600:  # 10 分钟超时
                print(f"runpod-worker-comfy - Job {job_id} timed out after {elapsed_time:.2f} seconds.")
                return {"error": "Job processing timed out after 10 minutes."}

            # 获取进度
            progress_info = get_progress(prompt_id)
            current_progress_state = (progress_info['status'], progress_info['progress'])

            # 处理连续404的情况
            if progress_info['status'] == 'pending' and progress_info['detail'] == 'Prompt not found in active queue':
                consecutive_404_count += 1
                if consecutive_404_count >= 5:  # 如果连续5次404
                    # 检查历史记录
                    history = get_history(prompt_id)
                    if prompt_id in history and "outputs" in history[prompt_id]:
                        print(f"runpod-worker-comfy - Workflow completed (found in history after 404s)")
                        outputs = history[prompt_id]["outputs"]
                        break
            else:
                consecutive_404_count = 0  # 重置计数器

            # 发送进度更新
            if progress_info and progress_info.get('status') != 'error' and current_progress_state != last_progress_sent:
                print(f"runpod-worker-comfy - Job {job_id} Progress: {progress_info['progress']}% - {progress_info['status']} - {progress_info['detail']}")
                try:
                    runpod.serverless.progress_update(job, progress_info)
                    last_progress_sent = current_progress_state
                except Exception as progress_err:
                    print(f"runpod-worker-comfy - Warning: Failed to send progress update: {progress_err}")

            # 检查是否完成
            if progress_info['status'] == 'completed':
                history = get_history(prompt_id)
                if prompt_id in history and "outputs" in history[prompt_id]:
                    print(f"runpod-worker-comfy - Workflow completed for Prompt ID: {prompt_id}")
                    outputs = history[prompt_id]["outputs"]
                    break

            # 等待下一次检查
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
            retries += 1

        # 7. 处理输出
        print(f"runpod-worker-comfy - Processing outputs for job {job_id}...")
        result = {}
        
        # 检查输出类型
        is_video_output = any(key in node_output for node_output in outputs.values() for key in ["videos", "gifs"])
        is_image_output = any("images" in node_output for node_output in outputs.values())

        if is_video_output:
            print("runpod-worker-comfy - Detected video/gif output type.")
            result = process_video_output(outputs, job_id)
        elif is_image_output:
            print("runpod-worker-comfy - Detected image output type.")
            result = process_output_images(outputs, job_id)
        else:
            print("runpod-worker-comfy - No recognizable image or video/gif outputs found.")
            result = {"status": "warning", "message": "Workflow completed, but no standard outputs were found."}

        # 确保总是有 status 字段
        if "status" not in result:
            result["status"] = "error"

        result["refresh_worker"] = REFRESH_WORKER
        print(f"runpod-worker-comfy - Job {job_id} finished with status: {result.get('status')}")
        return result

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