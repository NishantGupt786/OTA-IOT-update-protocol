#!/usr/bin/env python3

from setuptools import setup, find_packages

setup(
    name="iot-ota-cli",
    version="1.0.0",
    description="CLI tool for IoT Over-The-Air updates",
    author="IOT-Project",
    packages=find_packages(),
    install_requires=[
        "click>=8.0.0",
        "pyyaml>=6.0",
        "requests>=2.25.0",
        "rich>=13.0.0",
        "ansible-runner>=2.3.0",
        "paramiko>=2.9.0",
        "cryptography>=3.4.0",
    ],
    entry_points={
        "console_scripts": [
            "iot-ota=iot_ota_cli.main:cli",
        ],
    },
    python_requires=">=3.8",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
    ],
)