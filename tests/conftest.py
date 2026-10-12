# 让 pytest 能 import tools.*（把仓库根加入 sys.path）。
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))