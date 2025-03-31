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
from b2sdk.v2 import B2Api, InMemoryAccountInfo
import hashlib
import subprocess
import tempfile
from pathlib import Path

# Time to wait between API check attempts in milliseconds
COMFY_API_AVAILABLE_INTERVAL_MS = 50
# Maximum number of API check attempts
COMFY_API_AVAILABLE_MAX_RETRIES = 500
# Time to wait between poll attempts in milliseconds
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
# Maximum number of poll attempts
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 500))
# Host where ComfyUI is running
COMFY_HOST = "127.0.0.1:8188"
# Enforce a clean state after each job is done
# see https://docs.runpod.io/docs/handler-additional-controls#refresh-worker
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"

IMAGE_FILTER_BLUR_RADIUS = int(os.environ.get("IMAGE_FILTER_BLUR_RADIUS", 8))

# 添加视频相关的常量
VIDEO_OUTPUT_PATH = os.environ.get("VIDEO_OUTPUT_PATH", "/comfyui/output")
SUPPORTED_VIDEO_FORMATS = ['.mp4', '.webm', '.avi']

def validate_input(job_input):
    """验证输入数据"""
    if job_input is None:
        return None, "Please provide input"
    
    # 解析JSON字符串
    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input"
    
    # 验证workflow
    workflow = job_input.get("workflow")
    if workflow is None:
        return None, "Missing 'workflow' parameter"
    if not isinstance(workflow, dict):
        return None, "'workflow' must be a dictionary"
    
    # 验证images（如果存在）
    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list):
            return None, "'images' must be a list"
        for image in images:
            if not isinstance(image, dict):
                return None, "Each image must be a dictionary"
            if "name" not in image or "image" not in image:
                return None, "Each image must have 'name' and 'image' keys"
            if not isinstance(image["name"], str):
                return None, "Image name must be a string"
            if not isinstance(image["image"], str):
                return None, "Image data must be a string (base64 or URL)"
    
    return {"workflow": workflow, "images": images}, None


def check_server(url, retries=500, delay=50):
    """
    Check if a server is reachable via HTTP GET request

    Args:
    - url (str): The URL to check
    - retries (int, optional): The number of times to attempt connecting to the server. Default is 50
    - delay (int, optional): The time in milliseconds to wait between retries. Default is 500

    Returns:
    bool: True if the server is reachable within the given number of retries, otherwise False
    """

    for i in range(retries):
        try:
            response = requests.get(url)

            # If the response status code is 200, the server is up and running
            if response.status_code == 200:
                print(f"runpod-worker-comfy - API is reachable")
                return True
        except requests.RequestException as e:
            # If an exception occurs, the server may not be ready
            pass

        # Wait for the specified delay before retrying
        time.sleep(delay / 1000)

    print(
        f"runpod-worker-comfy - Failed to connect to server at {url} after {retries} attempts."
    )
    return False


def download_image(url):
    """Download image from URL and return as bytes"""
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.content
    except Exception as e:
        print(f"Error downloading image from URL: {str(e)}")
        return None


def upload_images(images):
    """
    Upload a list of base64 encoded images to the ComfyUI server using the /upload/image endpoint.

    Args:
        images (list): A list of dictionaries, each containing the 'name' of the image and the 'image' as a base64 encoded string.
        server_address (str): The address of the ComfyUI server.

    Returns:
        list: A list of responses from the server for each image upload.
    """
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}

    responses = []
    upload_errors = []

    print(f"runpod-worker-comfy - image(s) upload")

    for image in images:
        name = image["name"]
        image_data = image["image"]
        if isinstance(image_data, str) and (image_data.startswith('http://') or image_data.startswith('https://')):
            # 如果是URL，下载图片
            blob = download_image(image_data)
            if blob is None:
                return []
        else:
            # 原有的base64逻辑
            blob = base64.b64decode(image_data)

        # Prepare the form data
        files = {
            "image": (name, BytesIO(blob), "image/png"),
            "overwrite": (None, "true"),
        }

        # POST request to upload the image
        response = requests.post(f"http://{COMFY_HOST}/upload/image", files=files)
        if response.status_code != 200:
            upload_errors.append(f"Error uploading {name}: {response.text}")
        else:
            responses.append(f"Successfully uploaded {name}")

    if upload_errors:
        print(f"runpod-worker-comfy - image(s) upload with errors")
        return {
            "status": "error",
            "message": "Some images failed to upload",
            "details": upload_errors,
        }

    print(f"runpod-worker-comfy - image(s) upload complete")
    return {
        "status": "success",
        "message": "All images uploaded successfully",
        "details": responses,
    }


def queue_workflow(workflow):
    """
    Queue a workflow to be processed by ComfyUI

    Args:
        workflow (dict): A dictionary containing the workflow to be processed

    Returns:
        dict: The JSON response from ComfyUI after processing the workflow
    """

    # The top level element "prompt" is required by ComfyUI
    data = json.dumps({"prompt": workflow}).encode("utf-8")

    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())


def get_history(prompt_id):
    """
    Retrieve the history of a given prompt using its ID

    Args:
        prompt_id (str): The ID of the prompt whose history is to be retrieved

    Returns:
        dict: The history of the prompt, containing all the processing steps and results
    """
    with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}") as response:
        return json.loads(response.read())


def base64_encode(img_path):
    """
    Returns base64 encoded image.

    Args:
        img_path (str): The path to the image

    Returns:
        str: The base64 encoded image
    """
    with open(img_path, "rb") as image_file:
        encoded_string = base64.b64encode(image_file.read()).decode("utf-8")
        return f"{encoded_string}"


def upload_to_b2(local_file_path, file_name):
    """
    Upload a file to Backblaze B2 using b2sdk.
    
    Args:
        local_file_path (str): Path to the local file
        file_name (str): Name to use in B2 (including any path)
        
    Returns:
        str: URL of the uploaded file
    """
    try:
        # B2 setup
        info = InMemoryAccountInfo()
        b2_api = B2Api(info)
        application_key_id = os.environ.get('BUCKET_ACCESS_KEY_ID')
        application_key = os.environ.get('BUCKET_SECRET_ACCESS_KEY')
        endpoint_url = os.environ.get("BUCKET_ENDPOINT_URL", '')
        b2_api.authorize_account("production", application_key_id, application_key)

        # Get bucket
        bucket_name = os.environ.get('BUCKET_NAME')
        bucket = b2_api.get_bucket_by_name(bucket_name)
        
        # Upload file
        uploaded_file = bucket.upload_local_file(
            local_file=local_file_path,
            file_name=file_name
        )
        
        # Construct download URL
        download_url = f"{endpoint_url}/{bucket_name}/{file_name}"
        return download_url
    
    except Exception as e:
        print(f"runpod-worker-comfy - error uploading to B2: {str(e)}")
        return None


def process_output_images(outputs, job_id):
    """
    This function takes the "outputs" from image generation and the job ID,
    then determines the correct way to return the image, either as a direct URL
    to an AWS S3 bucket or as a base64 encoded string, depending on the
    environment configuration.

    Args:
        outputs (dict): A dictionary containing the outputs from image generation,
                        typically includes node IDs and their respective output data.
        job_id (str): The unique identifier for the job.

    Returns:
        dict: A dictionary with the status ('success' or 'error') and the message,
              which is either the URL to the image in the AWS S3 bucket or a base64
              encoded string of the image. In case of error, the message details the issue.

    The function works as follows:
    - It first determines the output path for the images from an environment variable,
      defaulting to "/comfyui/output" if not set.
    - It then iterates through the outputs to find the filenames of the generated images.
    - After confirming the existence of the image in the output folder, it checks if the
      AWS S3 bucket is configured via the BUCKET_ENDPOINT_URL environment variable.
    - If AWS S3 is configured, it uploads the image to the bucket and returns the URL.
    - If AWS S3 is not configured, it encodes the image in base64 and returns the string.
    - If the image file does not exist in the output folder, it returns an error status
      with a message indicating the missing image file.
    """

    # The path where ComfyUI stores the generated images
    COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")

    output_images = {}

    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image in node_output["images"]:
                output_images = os.path.join(image["subfolder"], image["filename"])

    print(f"runpod-worker-comfy - image generation is done")

    # expected image output folder
    local_image_path = f"{COMFY_OUTPUT_PATH}/{output_images}"

    print(f"runpod-worker-comfy - {local_image_path}")

    # The image is in the output folder
    if os.path.exists(local_image_path):
        if os.environ.get("BUCKET_ACCESS_KEY_ID", False):
            # 上传原始图片到 B2
            b2_file_path = f"{job_id}/{os.path.basename(local_image_path)}"
            image = upload_to_b2(local_image_path, b2_file_path)
            result = {
                "status": "success",
                "message": image
                #"blur": None
            }
            
            # 处理模糊版本
            try:
                # 创建模糊版本的文件名
                original_filename = os.path.basename(local_image_path)
                filename, ext = os.path.splitext(original_filename)
                blur_filename = hashlib.md5(original_filename.encode()).hexdigest() + ext
                local_blur_image_path = os.path.join(os.path.dirname(local_image_path), blur_filename)
                
                # 模糊处理
                with Image.open(local_image_path) as img:
                    blurred = img.filter(ImageFilter.GaussianBlur(radius=IMAGE_FILTER_BLUR_RADIUS))
                    blurred.save(local_blur_image_path)
                
                # 上传模糊版本到 B2
                b2_blur_path = f"{job_id}/{blur_filename}"
                blur_image = upload_to_b2(local_blur_image_path, b2_blur_path)
                #result["blur"] = blur_image
                print(f"runpod-worker-comfy - blurred image uploaded to B2: {blur_image}")
                
                # 清理临时文件
                if os.path.exists(local_blur_image_path):
                    os.remove(local_blur_image_path)
            except Exception as e:
                print(f"runpod-worker-comfy - error processing blurred image: {str(e)}")
            
            print(
                "runpod-worker-comfy - the image was generated and uploaded to B2"
            )
            return result
        else:
            # base64 image
            image = base64_encode(local_image_path)
            print(
                "runpod-worker-comfy - the image was generated and converted to base64"
            )

            return {
                "status": "success",
                "message": image,
            }
    else:
        print("runpod-worker-comfy - the image does not exist in the output folder")
        return {
            "status": "error",
            "message": f"the image does not exist in the specified output folder: {local_image_path}",
        }


def process_video_output(outputs, job_id):
    """
    处理视频输出并上传到B2
    
    Args:
        outputs (dict): 包含视频输出信息的字典
        job_id (str): 作业ID
    
    Returns:
        dict: 包含处理状态和视频URL的字典
    """
    output_videos = {}
    
    # 查找视频输出
    for node_id, node_output in outputs.items():
        if "videos" in node_output:
            for video in node_output["videos"]:
                output_videos = os.path.join(video["subfolder"], video["filename"])
    
    if not output_videos:
        return {
            "status": "error",
            "message": "No video output found in the results"
        }
    
    local_video_path = f"{VIDEO_OUTPUT_PATH}/{output_videos}"
    
    if not os.path.exists(local_video_path):
        return {
            "status": "error",
            "message": f"Video file not found at: {local_video_path}"
        }
    
    try:
        # 上传视频到B2
        b2_file_path = f"{job_id}/videos/{os.path.basename(local_video_path)}"
        video_url = upload_to_b2(local_video_path, b2_file_path)
        
        if not video_url:
            return {
                "status": "error",
                "message": "Failed to upload video to B2"
            }
        
        # 生成缩略图
        thumbnail_path = generate_video_thumbnail(local_video_path)
        thumbnail_url = None
        if thumbnail_path:
            b2_thumbnail_path = f"{job_id}/thumbnails/{os.path.basename(thumbnail_path)}"
            thumbnail_url = upload_to_b2(thumbnail_path, b2_thumbnail_path)
            # 清理临时缩略图
            os.remove(thumbnail_path)
        
        # 清理原始视频文件
        if os.path.exists(local_video_path):
            os.remove(local_video_path)
            print(f"runpod-worker-comfy - cleaned up video file: {local_video_path}")
            
        # 清理视频所在文件夹（如果为空）
        video_dir = os.path.dirname(local_video_path)
        try:
            if os.path.exists(video_dir) and not os.listdir(video_dir):
                os.rmdir(video_dir)
                print(f"runpod-worker-comfy - removed empty directory: {video_dir}")
        except Exception as e:
            print(f"runpod-worker-comfy - error removing directory: {str(e)}")
        
        return {
            "status": "success",
            "video_url": video_url,
            "thumbnail_url": thumbnail_url,
            "type": "video"
        }
        
    except Exception as e:
        # 如果发生错误，也尝试清理文件
        try:
            if os.path.exists(local_video_path):
                os.remove(local_video_path)
                print(f"runpod-worker-comfy - cleaned up video file after error: {local_video_path}")
        except Exception as cleanup_error:
            print(f"runpod-worker-comfy - error during cleanup: {str(cleanup_error)}")
            
        return {
            "status": "error",
            "message": f"Error processing video: {str(e)}"
        }

def generate_video_thumbnail(video_path, time_offset="00:00:01"):
    """
    从视频生成缩略图
    
    Args:
        video_path (str): 视频文件路径
        time_offset (str): 截取缩略图的时间点
    
    Returns:
        str: 缩略图文件路径，如果失败则返回None
    """
    try:
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp_file:
            thumbnail_path = tmp_file.name
            
        # 使用ffmpeg生成缩略图
        cmd = [
            'ffmpeg', '-i', video_path,
            '-ss', time_offset,
            '-vframes', '1',
            '-vf', 'scale=320:-1',
            '-y', thumbnail_path
        ]
        
        subprocess.run(cmd, check=True, capture_output=True)
        
        return thumbnail_path
    except Exception as e:
        print(f"Error generating thumbnail: {str(e)}")
        return None

def handler(job):
    """处理作业的主函数"""
    try:
        # 1. 验证输入
        validated_data, error_message = validate_input(job["input"])
        if error_message:
            return {"error": error_message}

        # 2. 确保ComfyUI API可用
        if not check_server(f"http://{COMFY_HOST}", 
                          COMFY_API_AVAILABLE_MAX_RETRIES,
                          COMFY_API_AVAILABLE_INTERVAL_MS):
            return {"error": "ComfyUI API is not available"}

        # 3. 上传输入图片（如果有）
        if validated_data.get("images"):
            upload_result = upload_images(validated_data["images"])
            if upload_result["status"] == "error":
                return upload_result

        # 4. 提交工作流
        try:
            queued_workflow = queue_workflow(validated_data["workflow"])
            prompt_id = queued_workflow["prompt_id"]
            print(f"runpod-worker-comfy - queued workflow with ID {prompt_id}")
        except Exception as e:
            return {"error": f"Error queuing workflow: {str(e)}"}

        # 5. 等待处理完成
        retries = 0
        while retries < COMFY_POLLING_MAX_RETRIES:
            history = get_history(prompt_id)
            if prompt_id in history and history[prompt_id].get("outputs"):
                break
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
            retries += 1
        else:
            return {"error": "Timeout waiting for results"}

        # 6. 处理输出
        outputs = history[prompt_id].get("outputs", {})
        
        # 确定输出类型并处理
        if any("videos" in node_output for node_output in outputs.values()):
            # 处理视频输出
            result = process_video_output(outputs, job["id"])
        else:
            # 处理图片输出（包括模糊处理）
            result = process_output_images(outputs, job["id"])
        
        result["refresh_worker"] = REFRESH_WORKER
        return result

    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}"}


# Start the handler only if this script is run directly
if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})