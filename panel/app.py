from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import uvicorn, sqlite3

app = FastAPI(title="SmartDNS Panel")
DB_PATH = "/etc/smartdns/core/database.db"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, ip TEXT)''')
    conn.commit()
    conn.close()

init_db()

@app.get("/panel", response_class=HTMLResponse)
def user_panel(request: Request):
    client_ip = request.client.host
    return f"""
    <!DOCTYPE html>
    <html dir="rtl" lang="fa">
    <head>
        <meta charset="UTF-8">
        <title>سرویس Smart DNS</title>
        <style>
            body {{ font-family: system-ui, sans-serif; background: #0f172a; color: #f8fafc; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }}
            .card {{ background: #1e293b; padding: 2rem; border-radius: 1rem; box-shadow: 0 10px 25px rgba(0,0,0,0.3); text-align: center; max-width: 400px; width: 100%; border: 1px solid #334155; }}
            .ip {{ background: #38bdf8; color: #0f172a; font-weight: bold; padding: 0.25rem 0.75rem; border-radius: 0.375rem; font-family: monospace; }}
            .btn {{ background: #0284c7; color: white; border: none; padding: 0.75rem 1.5rem; border-radius: 0.5rem; font-weight: bold; cursor: pointer; margin-top: 1rem; width: 100%; transition: 0.2s; }}
            .btn:hover {{ background: #0369a1; }}
        </style>
    </head>
    <body>
        <div class="card">
            <h2>⚡ سرویس Smart DNS فعال است</h2>
            <p>آی‌پی شناسایی‌شده: <span class="ip">{client_ip}</span></p>
            <p>برای فعال‌سازی روی سیستم یا کنسول بازی، این آی‌پی را به‌عنوان DNS ست کنید.</p>
            <button class="btn" onclick="alert('آی‌پی شما با موفقیت ثبت شد!')">ثبت IP جدید من</button>
        </div>
    </body>
    </html>
    """

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9443)
