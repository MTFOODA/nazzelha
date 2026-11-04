"""Compatibility entry point for the loopback Edge backend."""
import uvicorn
from web_bridge import app

if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=8000)
