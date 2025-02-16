Traceback (most recent call last):  File "/workspace/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/install.py", line 59, in <module>
    install_cupy()
  File "/workspace/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/install.py", line 37, in install_cupy
    cuda_home = get_cuda_home_path()
  File "/workspace/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/install.py", line 28, in get_cuda_home_path
    import torch
  File "/usr/local/lib/python3.10/dist-packages/torch/__init__.py", line 1477, in <module>
    from .functional import *  # noqa: F403
  File "/usr/local/lib/python3.10/dist-packages/torch/functional.py", line 9, in <module>
    import torch.nn.functional as F
  File "/usr/local/lib/python3.10/dist-packages/torch/nn/__init__.py", line 1, in <module>
    from .modules import *  # noqa: F403
  File "/usr/local/lib/python3.10/dist-packages/torch/nn/modules/__init__.py", line 35, in <module>
    from .transformer import TransformerEncoder, TransformerDecoder, \
  File "/usr/local/lib/python3.10/dist-packages/torch/nn/modules/transformer.py", line 20, in <module>
    device: torch.device = torch.device(torch._C._get_default_device()),  # torch.device('cpu'),
/usr/local/lib/python3.10/dist-packages/torch/nn/modules/transformer.py:20: UserWarning: Failed to initialize NumPy: _ARRAY_API not found (Triggered internally at ../torch/csrc/utils/tensor_numpy.cpp:84.)
  device: torch.device = torch.device(torch._C._get_default_device()),  # torch.device('cpu'),


  File "/usr/local/lib/python3.10/dist-packages/torio/_extension/utils.py", line 116, in _find_ffmpeg_extension
    ext = _find_versionsed_ffmpeg_extension(ffmpeg_ver)
  File "/usr/local/lib/python3.10/dist-packages/torio/_extension/utils.py", line 108, in _find_versionsed_ffmpeg_extension
    _load_lib(lib)
  File "/usr/local/lib/python3.10/dist-packages/torio/_extension/utils.py", line 94, in _load_lib
    torch.ops.load_library(path)
  File "/usr/local/lib/python3.10/dist-packages/torch/_ops.py", line 933, in load_library
    ctypes.CDLL(path)
  File "/usr/lib/python3.10/ctypes/__init__.py", line 374, in __init__
    self._handle = _dlopen(self._name, mode)
OSError: libavutil.so.58: cannot open shared object file: No such file or directory
Loading FFmpeg5
Failed to load FFmpeg5 extension.
Traceback (most recent call last):
  File "/usr/local/lib/python3.10/dist-packages/torio/_extension/utils.py", line 116, in _find_ffmpeg_extension
    ext = _find_versionsed_ffmpeg_extension(ffmpeg_ver)
  File "/usr/local/lib/python3.10/dist-packages/torio/_extension/utils.py", line 108, in _find_versionsed_ffmpeg_extension
    _load_lib(lib)
  File "/usr/local/lib/python3.10/dist-packages/torio/_extension/utils.py", line 94, in _load_lib
    torch.ops.load_library(path)
  File "/usr/local/lib/python3.10/dist-packages/torch/_ops.py", line 933, in load_library
    ctypes.CDLL(path)
  File "/usr/lib/python3.10/ctypes/__init__.py", line 374, in __init__
    self._handle = _dlopen(self._name, mode)
OSError: libavutil.so.57: cannot open shared object file: No such file or directory
Loading FFmpeg4
Successfully loaded FFmpeg4