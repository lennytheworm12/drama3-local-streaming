"""Runs the scorecard's gen.py under ComfyUI's embedded Python, whose ._pth leaves the script's folder off sys.path."""
import runpy
import sys

SC = r"C:\Users\bphan\PersonalProjects\drama3-local\scorecard"
sys.path.insert(0, SC)
sys.argv = [SC + r"\gen.py"] + sys.argv[1:]
runpy.run_path(SC + r"\gen.py", run_name="__main__")
