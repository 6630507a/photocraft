//! The live `photocraft://` resources over MCP (tokio duplex, in-process server).
//!
//! Kept in its own test binary: `photocraft://commands` reports each command's live enabled
//! state, and Edit › Purge › All is enabled while the process-wide render caches hold data. Tests
//! that render in parallel in the same process (as `mcp.rs` does) fill and clear those caches
//! between the two reads compared below, so this test needs a process to itself.

use photocraft_automation::PhotocraftMcp;
use rmcp::model::{CallToolRequestParams, CallToolResult, ClientConfig};
use rmcp::service::RunningService;
use rmcp::{ClientHandler, RoleClient, ServiceExt};
use serde_json::{Value, json};

#[derive(Clone, Default)]
struct Client;
impl ClientHandler for Client {
    fn get_info(&self) -> ClientConfig {
        ClientConfig::default()
    }
}

async fn connect(server: PhotocraftMcp) -> RunningService<RoleClient, Client> {
    let (s, c) = tokio::io::duplex(1 << 20);
    tokio::spawn(async move {
        if let Ok(running) = server.serve(s).await {
            let _ = running.waiting().await;
        }
    });
    Client.serve(c).await.expect("client init")
}

async fn call(client: &RunningService<RoleClient, Client>, name: &str, args: Value) -> CallToolResult {
    let mut p = CallToolRequestParams::new(name.to_owned());
    if let Value::Object(m) = args {
        p = p.with_arguments(m);
    }
    client.call_tool(p).await.expect("call_tool transport")
}

fn json_of(r: &CallToolResult) -> Value {
    let text = r.content.iter().filter_map(|c| c.as_text()).map(|t| t.text.clone()).collect::<Vec<_>>().join("\n");
    assert_ne!(r.is_error, Some(true), "tool error: {text}");
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("not JSON ({e}): {text}"))
}

#[tokio::test(flavor = "multi_thread")]
async fn convention_resources_are_live_json() {
    let client = connect(PhotocraftMcp::headless()).await;
    let resources = client.list_all_resources().await.unwrap();
    for uri in ["photocraft://document", "photocraft://commands"] {
        assert!(resources.iter().any(|r| r.uri == uri));
    }
    let read = async |uri: &str| {
        let r = client.read_resource(rmcp::model::ReadResourceRequestParams::new(uri)).await.unwrap();
        let v = serde_json::to_value(r).unwrap();
        serde_json::from_str::<Value>(v["contents"][0]["text"].as_str().unwrap()).unwrap()
    };
    assert!(read("photocraft://document").await["document"].is_null());
    json_of(&call(&client, "doc_new", json!({"width":8,"height":6})).await);
    assert_eq!(read("photocraft://document").await["width"], 8);
    assert_eq!(read("photocraft://commands").await, json_of(&call(&client, "command_list", json!({})).await));
    assert!(client.read_resource(rmcp::model::ReadResourceRequestParams::new("photocraft://missing")).await.is_err());
    let preview = call(&client, "render_preview", json!({"max_side":4})).await;
    assert!(preview.content.iter().any(|c| c.as_image().is_some()));
    client.cancel().await.unwrap();
}
