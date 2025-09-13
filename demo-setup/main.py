import requests
from datetime import datetime

def get_device_id():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("Serial"):
                    return line.strip().split(":")[1].strip()
    except:
        return "unknown-device"

def send_timestamp_webhook():
    webhook_url = "https://webhook.site/24341128-107e-4d7e-bd8a-ad6760a9f7a0"

    current_time = datetime.now()
    device_id = get_device_id()

    payload = {
        "timestamp": current_time.strftime("%Y-%m-%d %H:%M:%S"),
        "unix_timestamp": current_time.timestamp(),
        "device_id": device_id,
        "message": "Code is working!"
    }

    try:
        response = requests.post(webhook_url, json=payload)
        if response.status_code == 200:
            print(f"Payload sent successfully: {payload}")
        else:
            print(f"Failed: {response.status_code}")
    except Exception as e:
        print(f"Error: {e}")

send_timestamp_webhook()
