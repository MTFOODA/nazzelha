import os
import sys
from pathlib import Path

backend = Path(__file__).resolve().parent.parent / 'python_backend'
sys.path.insert(0, str(backend))
os.environ['NAZZELHA_PUBLIC_SERVER'] = '1'
os.environ.setdefault('NAZZELHA_QUICKJS_PATH', str(backend / 'bin/qjs'))
from serverless_api import create_serverless_app

app = create_serverless_app()
