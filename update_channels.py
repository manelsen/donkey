import json

with open("tasks/prd.json", "r") as f:
    data = json.load(f)

tasks = data["userStories"]
last_id = int(tasks[-1]["id"].split("-")[1])
last_task_id = tasks[-1]["id"]

def add_task(title, desc, criteria, deps):
    global last_id
    last_id += 1
    id_str = f"US-{last_id:03d}"
    tasks.append({
        "id": id_str,
        "title": title,
        "description": desc,
        "acceptanceCriteria": criteria + [
            "nim build src --mm:orc --styleCheck:error --warnings:error passes",
            "testament pattern 'tests/**/*.nim' passes"
        ],
        "priority": last_id,
        "passes": False,
        "notes": "",
        "dependsOn": deps
    })
    return id_str

us_ch_port = "US-041" # Ingress Port is US-041

# WeChat / WeCom
us_wechat_parse = add_task("WeChat Payload Parser", "Pure function to parse WeChat/WeCom XML/JSON.", ["Create domain/channels/wechat_pure.nim", "Implement parseMessage(payload)"], [us_ch_port])
us_wechat_adap = add_task("WeChat Webhook Adapter", "HTTP handler for WeChat/WeCom.", ["Create adapters/channels/wechat_webhook.nim"], [us_wechat_parse])

# Feishu / Lark
us_feishu_parse = add_task("Feishu Event Parser", "Pure function to parse Feishu/Lark JSON.", ["Create domain/channels/feishu_pure.nim", "Implement parseEvent(json)"], [us_ch_port])
us_feishu_adap = add_task("Feishu Webhook Adapter", "HTTP handler for Feishu/Lark events.", ["Create adapters/channels/feishu_webhook.nim"], [us_feishu_parse])

# QQ
us_qq_parse = add_task("QQ Message Parser", "Pure function to parse QQ payload.", ["Create domain/channels/qq_pure.nim", "Implement parseMessage(json)"], [us_ch_port])
us_qq_adap = add_task("QQ Webhook Adapter", "HTTP handler for QQ.", ["Create adapters/channels/qq_webhook.nim"], [us_qq_parse])

# DingTalk
us_ding_parse = add_task("DingTalk Event Parser", "Pure function to parse DingTalk payload.", ["Create domain/channels/dingtalk_pure.nim", "Implement parseEvent(json)"], [us_ch_port])
us_ding_adap = add_task("DingTalk Webhook Adapter", "HTTP handler for DingTalk.", ["Create adapters/channels/dingtalk_webhook.nim"], [us_ding_parse])

with open("tasks/prd.json", "w") as f:
    json.dump(data, f, indent=2)

# Re-generate Markdown
md = "# PRD: Donkey v1.0 — Paridade Integral (Atomic Tasks)\n\n"
md += "## 1. Visão Geral\nUm PRD hiper-granular contendo " + str(len(tasks)) + " tarefas atômicas, desenhadas para execução autônoma via AI agents. Cobre refatoração de core, providers LLM, memória vetorial, segurança, ferramentas nativas e canais de comunicação (incluindo ecossistema chinês).\n\n"
md += "## 2. Quality Gates\n- `nim build src --mm:orc --styleCheck:error --warnings:error` passes\n- `testament pattern \"tests/**/*.nim\"` passes\n\n"
md += "## 3. User Stories\n\n"

for t in tasks:
    md += f"### {t['id']}: {t['title']}\n"
    md += f"**Description:** {t['description']}\n"
    md += "**Acceptance Criteria:**\n"
    for c in t['acceptanceCriteria']:
        md += f"- [ ] {c}\n"
    md += "\n"

with open("tasks/prd-v1-stable.md", "w") as f:
    f.write(md)

print(f"Added Chinese channels. Total tasks: {len(tasks)}")
