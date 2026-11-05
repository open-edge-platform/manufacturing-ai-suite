# Static scanner fixture only; do not execute.
import subprocess

user_input = input("value: ")
subprocess.Popen("echo " + user_input, shell=True)