import requests
import json

api_key = "AIzaSyA3KAKmiwF69bYXJZBLNep3wrmZE6FYH9g"
url = f"https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key={api_key}"

payload = {
    "model": "models/text-embedding-004",
    "content": {
        "parts": [{
            "text": "Hello world"
        }]
    }
}

try:
    response = requests.post(url, headers={"Content-Type": "application/json"}, json=payload)
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"Error: {e}")
