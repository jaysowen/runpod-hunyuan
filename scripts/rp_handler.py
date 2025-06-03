import runpod
import json
import time
import os
import requests
import base64
import hashlib
from io import BytesIO
from PIL import Image, ImageFilter, ImageOps
from PIL.ExifTags import TAGS
from b2sdk.v2 import B2Api, InMemoryAccountInfo, UploadMode
import torch
import gc
import urllib3 # Added import

# Disable InsecureRequestWarning when verify=False is used with requests
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning) # Added to disable warnings

def check_exif_division_by_zero(image, image_blob=None):
    """
    检测图片EXIF数据是否可能导致除零错误
    使用实际的ImageOps.exif_transpose测试来检测问题
    返回: (has_problem, problem_description)
    """
    try:
        # 如果image为None，则尝试打开
        if image is None and image_blob is not None:
            image = Image.open(BytesIO(image_blob))
        elif image is None:
            return True, "No image object or blob provided"
        
        # **修复：移除MPO检测，因为MPO已经在format validation中转换了**
        # 只对JPEG格式进行EXIF检测，其他格式直接返回安全
        if image.format not in ['JPEG']:
            return False, f"Format {image.format} - No EXIF check needed"
        
        # 检查是否有EXIF数据
        if not hasattr(image, '_getexif') or image._getexif() is None:
            return False, "JPEG format but no EXIF data"
        
        exif_data = image._getexif()
        if not exif_data:
            return False, "JPEG format but empty EXIF data"
        
        # **关键改进：实际测试ImageOps.exif_transpose**
        try:
            # 创建图片副本进行测试，避免影响原图
            test_image = image.copy()
            ImageOps.exif_transpose(test_image)
            # 如果没有异常，说明EXIF数据是安全的
            return False, "JPEG EXIF data tested safe with ImageOps.exif_transpose"
        except (ZeroDivisionError, ValueError, KeyError, TypeError) as test_error:
            # 如果测试失败，说明确实有问题
            return True, f"JPEG EXIF ImageOps.exif_transpose test failed: {type(test_error).__name__}: {test_error}"
        except Exception as unexpected_error:
            # 其他未预期的错误也视为有问题
            return True, f"JPEG EXIF unexpected error during test: {type(unexpected_error).__name__}: {unexpected_error}"
        
    except Exception as e:
        # 如果检测过程出错，为安全起见返回True
        return True, f"Error checking EXIF: {str(e)}"

def fix_image_with_orientation_preserved(image_blob):
    """
    修复图片EXIF问题，同时尽力保持正确的方向
    安全地处理有问题的EXIF数据，避免除零错误
    """
    try:
        image = Image.open(BytesIO(image_blob))
        original_format = image.format
        
        # 首先尝试安全地应用EXIF方向信息
        try:
            # 尝试使用ImageOps.exif_transpose，这是最好的方法
            image = ImageOps.exif_transpose(image)
            print("runpod-worker-comfy - Successfully applied EXIF orientation")
        except (ZeroDivisionError, ValueError, KeyError, TypeError) as exif_error:
            print(f"runpod-worker-comfy - EXIF transpose failed ({type(exif_error).__name__}: {exif_error}), trying manual orientation handling...")
            
            # 如果ImageOps.exif_transpose失败，尝试手动处理方向
            try:
                exif_dict = image._getexif()
                if exif_dict is not None:
                    orientation = exif_dict.get(274)  # 274是Orientation标签
                    if orientation:
                        if orientation == 3:
                            image = image.rotate(180, expand=True)
                        elif orientation == 6:
                            image = image.rotate(270, expand=True)
                        elif orientation == 8:
                            image = image.rotate(90, expand=True)
                        print(f"runpod-worker-comfy - Manually applied orientation {orientation}")
                    else:
                        print("runpod-worker-comfy - No orientation tag found in EXIF")
                else:
                    print("runpod-worker-comfy - No EXIF data found")
            except Exception as manual_error:
                print(f"runpod-worker-comfy - Manual orientation handling also failed: {manual_error}")
                print("runpod-worker-comfy - Proceeding without orientation correction")
        
        # **修复：更安全的保存逻辑**
        output_buffer = BytesIO()
        
        # 确保图片模式正确
        if image.mode not in ['RGB', 'L']:
            if image.mode in ['RGBA', 'LA']:
                # 处理透明度
                background = Image.new('RGB', image.size, (255, 255, 255))
                if image.mode == 'RGBA':
                    background.paste(image, mask=image.split()[-1])
                else:  # LA
                    background.paste(image, mask=image.convert('RGBA').split()[-1])
                image = background
            else:
                image = image.convert('RGB')
        
        # **关键修复：移除有问题的exif参数**
        if original_format and original_format.upper() == 'JPEG':
            image.save(output_buffer, format='JPEG', quality=95, optimize=True)
        else:
            # 非JPEG格式转为JPEG
            image.save(output_buffer, format='JPEG', quality=95, optimize=True)
        
        print("runpod-worker-comfy - Successfully fixed EXIF issues and removed problematic data")
        return output_buffer.getvalue()
        
    except Exception as e:
        print(f"runpod-worker-comfy - Complete EXIF fix failed: {e}")
        
        # 最后的回退：简单地重新保存图片，移除所有EXIF数据
        try:
            image = Image.open(BytesIO(image_blob))
            output_buffer = BytesIO()
            # 强制保存为JPEG，不包含任何EXIF数据
            if image.mode in ['RGBA', 'LA']:
                # 处理透明度
                background = Image.new('RGB', image.size, (255, 255, 255))
                if image.mode == 'RGBA':
                    background.paste(image, mask=image.split()[-1])
                else:  # LA
                    background.paste(image, mask=image.convert('RGBA').split()[-1])
                image = background
            elif image.mode not in ['RGB', 'L']:
                image = image.convert('RGB')
            
            image.save(output_buffer, format='JPEG', quality=95, optimize=True)
            print("runpod-worker-comfy - Used fallback method: converted to JPEG without EXIF")
            return output_buffer.getvalue()
        except Exception as fallback_error:
            print(f"runpod-worker-comfy - Even fallback fix failed: {fallback_error}, returning original data")
            return image_blob

def check_and_resize_large_image(image, image_blob, name="image"):
    """
    检测图片是否超过PIL像素限制，如果超过则自动缩放
    接收已打开的image对象，避免重复打开
    注意：PIL限制已在upload_images函数中统一管理
    返回: (processed_blob, was_resized, description)
    """
    try:
        # 如果image为None，则尝试打开
        if image is None:
            # PIL限制已在upload_images函数中统一管理，无需重复设置
            image = Image.open(BytesIO(image_blob))
        
        width, height = image.size
        total_pixels = width * height
        
        print(f"runpod-worker-comfy - Image {name} size: {width}x{height} = {total_pixels:,} pixels")
        
        # 检查是否超过PIL默认限制
        if total_pixels > MAX_IMAGE_PIXELS:
            print(f"runpod-worker-comfy - Image {name} exceeds PIL limit ({MAX_IMAGE_PIXELS:,} pixels), resizing...")
            
            # 计算缩放比例，目标是略低于限制
            target_pixels = MAX_IMAGE_PIXELS * 0.9  # 留10%安全边距
            scale_factor = (target_pixels / total_pixels) ** 0.5
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            
            print(f"runpod-worker-comfy - Resizing {name} to {new_width}x{new_height} (scale: {scale_factor:.3f})")
            
            # 缩放图片
            resized_image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
            
            # 保存为新的blob
            output_buffer = BytesIO()
            format = image.format if image.format else 'JPEG'
            if format.upper() == 'JPEG':
                resized_image.save(output_buffer, format='JPEG', quality=95, optimize=True)
            else:
                resized_image.save(output_buffer, format=format)
            
            new_pixels = new_width * new_height
            return output_buffer.getvalue(), True, f"Resized from {total_pixels:,} to {new_pixels:,} pixels"
        
        else:
            print(f"runpod-worker-comfy - Image {name} size is within PIL limits, no resizing needed")
            return image_blob, False, f"Size OK: {total_pixels:,} pixels"
        
    except Exception as e:
        print(f"runpod-worker-comfy - Error checking image size for {name}: {e}")
        return image_blob, False, f"Size check failed: {str(e)}"

def quick_image_validation(image_blob, name="image"):
    """
    快速图片验证，只在必要时进行修复
    返回: (image_object, processed_blob, was_fixed, description)
    """
    try:
        # 快速验证：只检查能否打开，不做verify()
        temp_image = Image.open(BytesIO(image_blob))
        image_format = temp_image.format
        
        # 快速检查：只获取基本信息，不加载像素数据
        width, height = temp_image.size
        
        # **关键修复：检查MPO格式**
        if image_format == 'MPO':
            print(f"runpod-worker-comfy - Image {name} is MPO format, converting to JPEG for ComfyUI compatibility...")
            fixed_blob, was_fixed, desc = _convert_mpo_to_jpeg(image_blob, name)
            if was_fixed:
                fixed_image = Image.open(BytesIO(fixed_blob))
                return fixed_image, fixed_blob, True, desc
            else:
                return temp_image, image_blob, False, desc
        
        # 如果能正常获取信息，说明格式OK，返回image对象
        return temp_image, image_blob, False, f"Format {image_format} OK"
        
    except Exception as e:
        # 只有在出错时才进行修复
        error_msg = str(e).lower()
        
        # 快速判断是否是格式问题
        if any(keyword in error_msg for keyword in ["not a jpeg", "cannot identify", "syntaxerror", "truncated", "broken"]):
            print(f"runpod-worker-comfy - Image {name} validation failed: {e}, attempting fix...")
            fixed_blob, was_fixed, desc = _fix_corrupted_image(image_blob, name, str(e))
            if was_fixed:
                try:
                    # 重新打开修复后的图片
                    fixed_image = Image.open(BytesIO(fixed_blob))
                    return fixed_image, fixed_blob, True, desc
                except Exception as reopen_error:
                    print(f"runpod-worker-comfy - Failed to reopen fixed image: {reopen_error}")
                    return None, image_blob, False, f"Fix failed on reopen: {reopen_error}"
            else:
                # 修复失败，返回原始数据
                return None, image_blob, False, desc
        else:
            # 其他错误直接返回原数据
            return None, image_blob, False, f"Validation skipped: {str(e)}"

def _convert_mpo_to_jpeg(image_blob, name):
    """
    将MPO格式转换为标准JPEG格式
    MPO (Multi-Picture Object) 格式通常包含多个图片帧，我们提取第一个帧
    """
    try:
        print(f"runpod-worker-comfy - Converting MPO {name} to JPEG...")
        
        # 打开MPO文件
        mpo_image = Image.open(BytesIO(image_blob))
        
        # MPO文件可能包含多个帧，我们只取第一个帧（主图片）
        # 确保我们在第一帧
        mpo_image.seek(0)
        
        # 获取第一帧的图片数据
        # 创建一个新的图片对象，只包含第一帧
        first_frame = mpo_image.copy()
        
        # 确保颜色模式正确
        if first_frame.mode not in ['RGB', 'L']:
            if first_frame.mode in ['RGBA', 'LA']:
                # 处理透明度：创建白色背景
                background = Image.new('RGB', first_frame.size, (255, 255, 255))
                if first_frame.mode == 'RGBA':
                    background.paste(first_frame, mask=first_frame.split()[-1])
                else:  # LA
                    background.paste(first_frame, mask=first_frame.convert('RGBA').split()[-1])
                first_frame = background
            else:
                first_frame = first_frame.convert('RGB')
        
        # 保存为标准JPEG格式
        output_buffer = BytesIO()
        first_frame.save(output_buffer, format='JPEG', quality=95, optimize=True)
        
        print(f"runpod-worker-comfy - Successfully converted MPO {name} to JPEG")
        return output_buffer.getvalue(), True, "Converted MPO to JPEG"
        
    except Exception as e:
        print(f"runpod-worker-comfy - MPO conversion failed for {name}: {e}")
        # 如果MPO转换失败，尝试通用的图片修复
        return _fix_corrupted_image(image_blob, name, f"MPO conversion failed: {e}")

def _fix_corrupted_image(image_blob, name, original_error):
    """
    仅在确认格式损坏时才执行的修复函数
    注意：PIL限制已在upload_images函数中统一管理
    """
    try:
        print(f"runpod-worker-comfy - Fixing corrupted image {name}: {original_error}")
        
        # 不需要设置PIL限制，因为upload_images函数已经统一管理
        # 尝试强制打开并转换为JPEG
        temp_image = Image.open(BytesIO(image_blob))
        
        # 快速模式转换
        if temp_image.mode not in ['RGB', 'L']:
            if temp_image.mode in ['RGBA', 'LA']:
                # 创建白色背景
                background = Image.new('RGB', temp_image.size, (255, 255, 255))
                if temp_image.mode == 'RGBA':
                    background.paste(temp_image, mask=temp_image.split()[-1])
                else:  # LA
                    background.paste(temp_image, mask=temp_image.convert('RGBA').split()[-1])
                temp_image = background
            else:
                temp_image = temp_image.convert('RGB')
        
        # 保存为JPEG
        output_buffer = BytesIO()
        temp_image.save(output_buffer, format='JPEG', quality=95)
        
        print(f"runpod-worker-comfy - Successfully fixed corrupted image {name}")
        return output_buffer.getvalue(), True, "Fixed: converted to JPEG"
        
    except Exception as fix_error:
        print(f"runpod-worker-comfy - Fix failed for {name}: {fix_error}")
        return image_blob, False, f"Fix failed: {fix_error}"

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
# PIL图片像素限制 (使用PIL默认限制作为阈值)
MAX_IMAGE_PIXELS = 178956970  # PIL默认限制，约1.79亿像素

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
    """将文件上传到 B2 存储，设置 Content-Disposition 为 attachment"""
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
            print(f"runpod-worker-comfy - 文件不存在: {local_file_path}")
            return None
            
        if not os.access(local_file_path, os.R_OK):
            print(f"runpod-worker-comfy - 文件不可读: {local_file_path}")
            return None

        # 检查文件是否为空
        file_size = os.path.getsize(local_file_path)
        if file_size == 0:
            print(f"runpod-worker-comfy - 文件为空: {local_file_path}")
            return None

        # 从文件名中提取基础文件名（用于 Content-Disposition）
        base_filename = os.path.basename(file_name)
        
        # 调试信息：输出原始 file_name 和提取的 base_filename
        print(f"runpod-worker-comfy - DEBUG: file_name = '{file_name}'")
        print(f"runpod-worker-comfy - DEBUG: base_filename = '{base_filename}'")
        
        # 根据文件扩展名设置正确的 Content-Type
        file_extension = os.path.splitext(base_filename)[1].lower()
        content_type_map = {
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.png': 'image/png',
            '.gif': 'image/gif',
            '.webp': 'image/webp',
            '.bmp': 'image/bmp',
            '.tiff': 'image/tiff',
            '.mp4': 'video/mp4',
            '.webm': 'video/webm',
            '.avi': 'video/x-msvideo',
            '.mov': 'video/quicktime'
        }
        
        content_type = content_type_map.get(file_extension, 'application/octet-stream')
        
        # 尝试多种设置 Content-Disposition 的方法
        file_info = {
            # 方法1: 标准HTTP头部名称
            'Content-Disposition': f'attachment; filename="{base_filename}"',
            # 方法2: B2特定前缀
            'b2-content-disposition': f'attachment; filename="{base_filename}"',
            # 方法3: 小写版本
            'content-disposition': f'attachment; filename="{base_filename}"'
        }

        print(f"runpod-worker-comfy - 开始上传文件到 B2: {file_name} (大小: {file_size} bytes)")
        print(f"runpod-worker-comfy - Content-Type: {content_type}")
        print(f"runpod-worker-comfy - File Info: {file_info}")

        # 尝试直接使用 content_disposition 参数 + file_info
        try:
            uploaded_file = b2_bucket_instance.upload_local_file(
                local_file=local_file_path,
                file_name=file_name,
                content_type=content_type,
                content_disposition=f'attachment; filename="{base_filename}"',
                file_info=file_info
            )
            print(f"runpod-worker-comfy - 使用 content_disposition 参数 + file_info 上传成功")
        except Exception as e1:
            print(f"runpod-worker-comfy - content_disposition 参数失败: {e1}")
            # 回退到只使用 file_info
            try:
                uploaded_file = b2_bucket_instance.upload_local_file(
                    local_file=local_file_path,
                    file_name=file_name,
                    content_type=content_type,
                    file_info=file_info
                )
                print(f"runpod-worker-comfy - 使用 file_info 上传成功")
            except Exception as e2:
                print(f"runpod-worker-comfy - file_info 也失败: {e2}")
                # 最后回退到基本上传
                uploaded_file = b2_bucket_instance.upload_local_file(
                    local_file=local_file_path,
                    file_name=file_name,
                    content_type=content_type
                )
                print(f"runpod-worker-comfy - 使用基本上传（无 Content-Disposition）")

        download_url = f"{endpoint_url}/{bucket_name}/{file_name}"
        
        print(f"runpod-worker-comfy - 文件已上传到 B2: {download_url}")
        return download_url

    except Exception as e:
        print(f"runpod-worker-comfy - 上传失败: {str(e)}")
        print(f"runpod-worker-comfy - 文件路径: {local_file_path}")
        print(f"runpod-worker-comfy - 目标文件名: {file_name}")
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

    # 统一设置PIL限制，避免在各个函数中重复设置
    original_pil_limit = Image.MAX_IMAGE_PIXELS
    Image.MAX_IMAGE_PIXELS = None  # 临时移除限制，允许处理超大图片
    
    # 性能统计
    performance_stats = {
        "image_opens_saved": 0,
        "pil_limit_sets_saved": 0,
        "total_images": len(images)
    }
    
    try:
        # 确保输入目录存在
        input_dir = "/workspace/ComfyUI/input"
        os.makedirs(input_dir, exist_ok=True)
        
        uploaded_files_info = []
        errors = []
        print(f"runpod-worker-comfy - Uploading {len(images)} image(s) to ComfyUI with optimized processing...")

        for image_input in images:
            name = image_input["name"]
            image_data_str = image_input["image"]
            blob = None
            local_path = None  # 添加这行初始化

            # 确保文件名是安全的
            safe_filename = os.path.basename(name)
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
                    import traceback
                    tb_str = traceback.format_exc()
                    error_msg = f"Error downloading image '{name}' from URL: {e}. Traceback: {tb_str}"
                    print(f"runpod-worker-comfy - {error_msg}")
                    errors.append(error_msg)
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
                    # --- 高性能图片处理流程 ---
                    # 1. 快速格式验证（只在出错时修复）
                    processed_image, processed_blob, was_fixed, format_desc = quick_image_validation(blob, name)
                    
                    if was_fixed:
                        print(f"runpod-worker-comfy - {name} was repaired: {format_desc}")
                        # 重新获取修复后的格式
                        if processed_image:
                            image_format = processed_image.format
                            print(f"runpod-worker-comfy - Fixed image format: {image_format} for {name}")
                        else:
                            image_format = "JPEG"  # 如果无法获取，默认为JPEG
                        performance_stats["image_opens_saved"] += 1  # 避免了重复打开
                    else:
                        # 正常情况：从已有的image对象获取格式
                        if processed_image:
                            image_format = processed_image.format
                            print(f"runpod-worker-comfy - Detected image format: {image_format} for {name}")
                            performance_stats["image_opens_saved"] += 1  # 避免了重复打开
                        else:
                            print(f"runpod-worker-comfy - Warning: Could not get image object for {name}")
                            image_format = "Unknown"
                    
                    # 2. 尺寸检测（使用已有的image对象）
                    processed_blob, was_resized, size_desc = check_and_resize_large_image(processed_image, processed_blob, name)
                    performance_stats["image_opens_saved"] += 1 if processed_image else 0  # 避免了重复打开
                    
                    if was_resized:
                        print(f"runpod-worker-comfy - {name} was resized: {size_desc}")
                        # 已经处理过的图片，不需要再做EXIF检测
                        processed_image = None  # 重置image对象，因为已经缩放
                    else:
                        print(f"runpod-worker-comfy - {name} size check: {size_desc}")
                    
                    # 3. EXIF检测（更安全的检测逻辑）
                    if not was_resized and processed_image:
                        # 重新检查图片格式，避免依赖可能不准确的image_format变量
                        actual_format = processed_image.format
                        if actual_format == 'JPEG':
                            print(f"runpod-worker-comfy - JPEG detected, checking EXIF data for potential issues in {name}...")
                            has_problem, problem_desc = check_exif_division_by_zero(processed_image)
                            performance_stats["image_opens_saved"] += 1  # 避免了重复打开
                            
                            if has_problem:
                                print(f"runpod-worker-comfy - EXIF issue detected in {name}: {problem_desc}")
                                print(f"runpod-worker-comfy - Applying smart fix to preserve orientation...")
                                
                                # 修复EXIF问题，保持方向
                                processed_blob = fix_image_with_orientation_preserved(processed_blob)
                                print(f"runpod-worker-comfy - Successfully fixed EXIF issues in {name}")
                            else: 
                                print(f"runpod-worker-comfy - JPEG EXIF data is safe in {name}: {problem_desc}")
                        else:
                            print(f"runpod-worker-comfy - {actual_format} format, no EXIF check needed for {name}")
                    else:
                        if was_resized:
                            print(f"runpod-worker-comfy - {name} was resized, skipping EXIF check")
                        else:
                            print(f"runpod-worker-comfy - No valid image object for EXIF check in {name}")

                    # 统计PIL限制设置的节省
                    # 原来每个函数都会设置/恢复PIL限制，现在统一管理节省了：
                    # - check_and_resize_large_image: 2次操作 (设置+恢复)
                    # - _fix_corrupted_image: 2次操作 (设置+恢复) 
                    # - 总共节省4-6次PIL限制操作每张图片
                    performance_stats["pil_limit_sets_saved"] += 6  # 每张图片节省最多6次PIL限制设置

                    # 保存处理后的图片数据到本地文件
                    with open(local_path, 'wb') as f:
                        f.write(processed_blob) 
                    print(f"runpod-worker-comfy - Saved image to {local_path}")

                    # 上传到ComfyUI API，让ComfyUI自行判断文件类型
                    print(f"runpod-worker-comfy - Uploading '{name}' via ComfyUI API...")
                    with open(local_path, 'rb') as f_upload:
                        files = {
                            "image": (safe_filename, f_upload),
                            "overwrite": (None, "true"),
                        }
                        upload_url = f"http://{COMFY_HOST}/upload/image"
                        response = requests.post(upload_url, files=files, timeout=30)

                    if response.status_code == 200:
                        uploaded_info = response.json()
                        uploaded_info['local_path'] = local_path
                        uploaded_files_info.append(uploaded_info)
                        print(f"runpod-worker-comfy - Successfully uploaded '{name}' to ComfyUI.")
                    else:
                        errors.append(f"Error uploading '{name}' to ComfyUI API: {response.status_code} - {response.text}")
                        cleanup_local_file(local_path, f"failed ComfyUI API upload for image {name}")

                except Exception as e:
                    import traceback
                    tb_str = traceback.format_exc()
                    error_msg = f"Error during image processing/saving for '{name}': {e}. Traceback: {tb_str}"
                    print(f"runpod-worker-comfy - {error_msg}")
                    errors.append(error_msg)
                    if local_path:  # 添加检查，避免None值
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
            # 输出性能统计
            print(f"runpod-worker-comfy - Performance optimization results:")
            print(f"  - Images processed: {performance_stats['total_images']}")
            print(f"  - Image opens saved: {performance_stats['image_opens_saved']} (~{performance_stats['image_opens_saved']/max(1,performance_stats['total_images']):.1f} per image)")
            print(f"  - PIL limit sets saved: {performance_stats['pil_limit_sets_saved']} (~{performance_stats['pil_limit_sets_saved']/max(1,performance_stats['total_images']):.1f} per image)")
            estimated_time_saved = performance_stats['image_opens_saved'] * 0.1 + performance_stats['pil_limit_sets_saved'] * 0.01
            print(f"  - Estimated time saved: ~{estimated_time_saved:.2f} seconds")
            
            return {
                "status": "success",
                "message": "All images uploaded successfully.",
                "details": uploaded_files_info # 返回 ComfyUI 的文件信息
            }
    finally:
        Image.MAX_IMAGE_PIXELS = original_pil_limit  # 恢复PIL限制

def queue_workflow(workflow):
    """向 ComfyUI 提交工作流"""
    try:
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

                    # 计算缩略图尺寸，保持原图比例并确保清晰度
                    # 让较长的边达到 thumbnail_width，保持原有的清晰度
                    if original_width >= original_height:
                        # 横图：宽度设为 thumbnail_width，按比例计算高度
                        new_width = thumbnail_width
                        new_height = round((original_height * thumbnail_width) / original_width)
                    else:
                        # 竖图：高度设为 thumbnail_width，按比例计算宽度  
                        new_height = thumbnail_width
                        new_width = round((original_width * thumbnail_width) / original_height)
                    
                    # 确保尺寸至少为1
                    new_width = max(1, new_width)
                    new_height = max(1, new_height)
                    
                    thumbnail_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                    
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
    thumb_quality_param = job_input_payload.get("thumbnail_quality", 90)
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
            thumbnail_quality = 90 # Default if out of range
            print(f"runpod-worker-comfy - Invalid thumbnail_quality, using default {thumbnail_quality}")
    except ValueError:
        thumbnail_quality = 90
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