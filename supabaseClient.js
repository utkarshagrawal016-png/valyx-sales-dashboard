// VALYX Supabase Client Setup & RPC Integration
// Calls RPC function: get_sales_dashboard(report_data DATE)

let supabaseClient = null;

function showErrorOverlay(msg) {
  let overlay = document.getElementById("supabase-error-overlay");
  if (!overlay) {
    overlay = document.createElement("div");
    overlay.id = "supabase-error-overlay";
    overlay.style.position = "fixed";
    overlay.style.top = "0";
    overlay.style.left = "0";
    overlay.style.width = "100%";
    overlay.style.height = "100%";
    overlay.style.backgroundColor = "rgba(15, 23, 42, 0.95)";
    overlay.style.color = "#f8fafc";
    overlay.style.display = "flex";
    overlay.style.flexDirection = "column";
    overlay.style.alignItems = "center";
    overlay.style.justifyContent = "center";
    overlay.style.zIndex = "99999";
    overlay.style.padding = "20px";
    overlay.style.fontFamily = "Outfit, Inter, system-ui, sans-serif";
    overlay.style.textAlign = "center";

    const box = document.createElement("div");
    box.style.backgroundColor = "#1e293b";
    box.style.border = "2px solid #ff5500";
    box.style.borderRadius = "12px";
    box.style.padding = "30px";
    box.style.maxWidth = "550px";
    box.style.boxShadow = "0 20px 25px -5px rgba(0, 0, 0, 0.5)";

    const title = document.createElement("h2");
    title.textContent = "VALYX - Configuration Required";
    title.style.color = "#ff5500";
    title.style.marginTop = "0";
    title.style.marginBottom = "15px";
    title.style.fontSize = "22px";
    title.style.fontWeight = "700";

    const text = document.createElement("p");
    text.id = "supabase-error-text";
    text.style.fontSize = "14px";
    text.style.lineHeight = "1.6";
    text.style.color = "#cbd5e1";
    text.style.marginBottom = "25px";

    const instructions = document.createElement("div");
    instructions.style.textAlign = "left";
    instructions.style.backgroundColor = "#0f172a";
    instructions.style.padding = "15px 20px";
    instructions.style.borderRadius = "8px";
    instructions.style.fontSize = "13px";
    instructions.style.color = "#94a3b8";
    instructions.innerHTML = `
      <div style="font-weight: 700; color: #ff5500; text-transform: uppercase; font-size: 11px; margin-bottom: 8px; letter-spacing: 0.05em;">Setup Instructions:</div>
      <ol style="margin: 0; padding-left: 20px; line-height: 1.6;">
        <li>Create a file named <code style="color: #f8fafc; font-family: monospace;">config.js</code> in the project root.</li>
        <li>Copy the contents from <code style="color: #f8fafc; font-family: monospace;">config.example.js</code>.</li>
        <li>Replace the placeholders with your own Supabase project credentials.</li>
        <li>Refresh the browser window.</li>
      </ol>
    `;

    box.appendChild(title);
    box.appendChild(text);
    box.appendChild(instructions);
    overlay.appendChild(box);
    document.body.appendChild(overlay);
  }
  document.getElementById("supabase-error-text").textContent = msg;
}

function initSupabase() {
  const url = window.ENV ? window.ENV.SUPABASE_URL : null;
  const key = window.ENV ? window.ENV.SUPABASE_ANON_KEY : null;

  const isInvalidUrl = !url || url === "YOUR_SUPABASE_URL" || url === "YOUR_URL" || url.includes("pcenxwfhavneypapwbxi");
  const isInvalidKey = !key || key === "YOUR_SUPABASE_ANON_KEY" || key === "YOUR_KEY" || key.includes("sb_publishable_GGbm");

  if (isInvalidUrl || isInvalidKey) {
    const errorMsg = "Your Supabase credentials are not configured correctly. The application needs a valid database URL and anonymous key to connect to your project.";
    console.error("Supabase Init Failed: " + errorMsg);
    showErrorOverlay(errorMsg);
    return;
  }

  if (window.supabase && typeof window.supabase.createClient === 'function') {
    try {
      supabaseClient = window.supabase.createClient(url, key);
      console.log("VALYX - Connected to Supabase Project:", url);
    } catch (e) {
      console.error("Error creating Supabase client:", e);
      showErrorOverlay("Error creating Supabase client: " + e.message);
    }
  } else {
    const errorMsg = "Supabase JS Library not found! Check your network connection or the CDN link inside index.html.";
    console.error(errorMsg);
    showErrorOverlay(errorMsg);
  }
}

async function checkSupabaseConnection() {
  if (!supabaseClient) initSupabase();
  if (!supabaseClient) {
    return { connected: false, message: 'Supabase client not initialized' };
  }

  try {
    const { data, error } = await supabaseClient.rpc('get_sales_dashboard', { report_data: '2026-05-17' });
    if (error) {
      console.warn("RPC call check failed:", error.message);
      return { connected: true, rpcAvailable: false, message: `Connected (RPC Error: ${error.message})` };
    }
    return { connected: true, rpcAvailable: true, message: 'Live Connected to Supabase RPC' };
  } catch (err) {
    return { connected: false, rpcAvailable: false, message: `Connection Error: ${err.message}` };
  }
}

async function fetchSalesDashboardRPC(reportDate = '2026-05-17') {
  if (!supabaseClient) initSupabase();
  if (!supabaseClient) return null;

  try {
    const { data, error } = await supabaseClient.rpc('get_sales_dashboard', { report_data: reportDate });
    if (error) {
      console.error("RPC get_sales_dashboard error:", error);
      return null;
    }
    if (data && data.length > 0) {
      return data[0]; // returns object with { daily_metrics, month_metrics, kpi_metrics, sales_rep_metrics, destination_metrics, wallet_metrics }
    }
  } catch (err) {
    console.error("Exception calling get_sales_dashboard RPC:", err);
  }
  return null;
}

window.VALYXDataService = {
  initSupabase,
  checkSupabaseConnection,
  fetchSalesDashboardRPC
};
