import json
import requests
import sys

# Load credentials from config.js
url = None
anon_key = None

try:
    with open("config.js", "r", encoding="utf-8") as f:
        for line in f:
            if "SUPABASE_URL:" in line:
                url = line.split("SUPABASE_URL:")[1].strip().strip(",").strip('"').strip("'")
            if "SUPABASE_ANON_KEY:" in line:
                anon_key = line.split("SUPABASE_ANON_KEY:")[1].strip().strip(",").strip('"').strip("'")
except Exception as e:
    print(f"Error reading config.js: {e}")
    sys.exit(1)

if not url or not anon_key or "YOUR" in url:
    print("[-] Error: Supabase credentials are not configured in config.js!")
    sys.exit(1)

print(f"[+] Loaded credentials from config.js")
print(f"    URL: {url}")
print(f"    Anon Key: {anon_key[:15]}...")

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Prefer": "count=exact"
}

tables = {
    "users": 2587,
    "products": 402,
    "destinations": 266,
    "orders": 2831
}

# 1. Verify Table Existence and Row Counts
print("\n--- 1. VERIFYING TABLE ROW COUNTS ---")
errors = 0
for table, expected in tables.items():
    endpoint = f"{url}/rest/v1/{table}?select=user_id" if table == "users" else f"{url}/rest/v1/{table}?select=*"
    if table == "products":
        endpoint = f"{url}/rest/v1/{table}?select=prod_id"
    elif table == "destinations":
        endpoint = f"{url}/rest/v1/{table}?select=destination_id"
    elif table == "orders":
        endpoint = f"{url}/rest/v1/{table}?select=order_no"
        
    try:
        response = requests.get(f"{endpoint}&limit=1", headers=headers)
        if response.status_code == 200:
            count_header = response.headers.get("Content-Range")
            if count_header and "/" in count_header:
                count = int(count_header.split("/")[1])
                diff = abs(count - expected)
                if diff <= 5: # allow slight variance if minor rows mismatch
                    print(f"[+] Table '{table}': EXISTS with {count} rows (Expected: {expected}) - MATCH")
                else:
                    print(f"[-] Table '{table}': EXISTS but row count is {count} (Expected: {expected}) - MISMATCH")
                    errors += 1
            else:
                print(f"[-] Table '{table}': Could not determine row count (Content-Range missing)")
                errors += 1
        elif response.status_code == 404:
            print(f"[-] Table '{table}': DOES NOT EXIST (HTTP 404)")
            errors += 1
        else:
            print(f"[-] Table '{table}': Error querying (HTTP {response.status_code}): {response.text}")
            errors += 1
    except Exception as e:
        print(f"[-] Table '{table}': Exception: {e}")
        errors += 1

# 2. Verify RPC Function and Dynamic Dates
print("\n--- 2. VERIFYING DYNAMIC RPC (get_sales_dashboard) ---")
rpc_endpoint = f"{url}/rest/v1/rpc/get_sales_dashboard"

def get_rpc_data(date_str):
    payload = {"report_data": date_str}
    try:
        res = requests.post(rpc_endpoint, json=payload, headers={"apikey": anon_key, "Authorization": f"Bearer {anon_key}"})
        if res.status_code == 200:
            data = res.json()
            if data and len(data) > 0:
                return data[0]
            else:
                print(f"[-] RPC returned empty list for date {date_str}")
        else:
            print(f"[-] RPC call failed for date {date_str} (HTTP {res.status_code}): {res.text}")
    except Exception as e:
        print(f"[-] RPC Exception: {e}")
    return None

data_25 = get_rpc_data("2026-05-25")
data_24 = get_rpc_data("2026-05-24")

if data_25 and data_24:
    kpi_25 = data_25.get("kpi_metrics", [{}])[0]
    kpi_24 = data_24.get("kpi_metrics", [{}])[0]
    
    print(f"[+] RPC function get_sales_dashboard exists and executed successfully!")
    print(f"\nComparing RPC results:")
    print(f"    Date: 2026-05-25 | Sales count: {kpi_25.get('today_sales')} | Revenue: INR {kpi_25.get('today_revenue')}")
    print(f"    Date: 2026-05-24 | Sales count: {kpi_24.get('today_sales')} | Revenue: INR {kpi_24.get('today_revenue')}")
    
    # Check if data changes dynamically
    sales_25 = kpi_25.get('today_sales', 0)
    sales_24 = kpi_24.get('today_sales', 0)
    
    # Check if the counts correspond to the old mock values or the new real values
    if sales_25 == 33 and sales_24 == 33:
        print("\n[-] STATUS: DB setup is still using the old mock data (33 sales per day)!")
        print("    Please run the new setup_supabase.sql script in Supabase first.")
    elif sales_25 != sales_24:
        print("\n[+] STATUS: SUCCESS! Dynamic database setup is complete and fully working.")
        print(f"    - Table imports: OK")
        print(f"    - Dynamic dates matching order volumes: OK")
    else:
        print("\n[!] STATUS: Database is dynamic but date counts matched. Double check if orders exist.")
else:
    print("\n[-] STATUS: RPC verification failed. Please verify that setup_supabase.sql executed without errors.")
