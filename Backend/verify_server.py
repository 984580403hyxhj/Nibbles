
import requests
import json
import time

BASE_URL = "http://localhost:8000"

def test_fetch():
    print("Testing /fetch endpoint...")
    url = f"{BASE_URL}/fetch"
    # Example URL (using a simple one or the user's example if I had one)
    # Using a generic tech article or Jina's own example
    payload = {"url": "https://www.example.com"} 
    
    try:
        response = requests.post(url, json=payload)
        print(f"Status: {response.status_code}")
        if response.status_code == 200:
            print("Response preview:", response.json().get("content", "")[:100])
            return True
        else:
            print("Error:", response.text)
            return False
    except Exception as e:
        print(f"Failed to connect: {e}")
        return False

def test_health():
    print("\nTesting /health endpoint...")
    try:
        response = requests.get(f"{BASE_URL}/health")
        print(f"Status: {response.status_code}")
        print("Response:", response.json())
        return response.status_code == 200
    except Exception as e:
        print(f"Failed to connect: {e}")
        return False

if __name__ == "__main__":
    print(f"Verifying server at {BASE_URL}")
    print("Ensure the server is running (python server.py)")
    
    if test_health():
        test_fetch()
    else:
        print("Health check failed. Is the server running?")
