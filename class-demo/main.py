import requests
from datetime import datetime


def send_timestamp_webhook():
    webhook_url = "https://webhook.site/9dcdcd3f-a848-496d-b9ca-07dfb1760ef5"  # Get one from webhook.site
    
    # Generate current timestamp
    current_time = datetime.now()
    timestamp_data = {
        "timestamp": current_time.strftime("%Y-%m-%d %H:%M:%S"),
        "unix_timestamp": current_time.timestamp(),
        "message": "nishant & sumit!"
    }
    
    try:
        response = requests.post(webhook_url, json=timestamp_data)
        if response.status_code == 200:
            print(f"Timestamp sent successfully now: {timestamp_data['timestamp']}")
        else:
            print(f"Failed to send timestamp: {response.status_code}")
    except Exception as e:
        print(f"Error sending timestamp: {e}")


# Call the function
send_timestamp_webhook()
