#!/usr/bin/env python3

import json
from http.server import BaseHTTPRequestHandler, HTTPServer


PROFILE_UUID = "11111111-1111-4111-8111-111111111111"
LEGACY_PROFILE_UUID = "99999999-9999-4999-8999-999999999999"
NODE_UUID = "22222222-2222-4222-8222-222222222222"
SQUAD_UUID = "33333333-3333-4333-8333-333333333333"
TEMPLATE_UUID = "44444444-4444-4444-8444-444444444444"

state = {
    "profiles": [{
        "uuid": LEGACY_PROFILE_UUID,
        "name": "Existing node",
        "config": {"inbounds": [
            {"tag": "VLESS_RAW_REALITY"},
            {"tag": "VLESS_XHTTP_CADDY"},
            {"tag": "HYSTERIA2_TLS"},
            {"tag": "VLESS_GRPC_CADDY"},
        ]},
        "inbounds": [
            {"uuid": f"77777777-7777-4777-8777-{index:012d}", "tag": tag}
            for index, tag in enumerate((
                "VLESS_RAW_REALITY",
                "VLESS_XHTTP_CADDY",
                "HYSTERIA2_TLS",
                "VLESS_GRPC_CADDY",
            ), 1)
        ],
    }],
    "nodes": [{
        "uuid": NODE_UUID,
        "name": "Test node",
        "address": "node.example.com",
        "port": 2222,
        "configProfile": {"activeConfigProfileUuid": None, "activeInbounds": []},
    }],
    "squads": [{"uuid": SQUAD_UUID, "name": "Default", "inbounds": []}],
    "templates": [],
    "hosts": [],
}


def inbound_uuid(index):
    return f"55555555-5555-4555-8555-{index:012d}"


def profile_from(body):
    inbounds = []
    for index, inbound in enumerate(body["config"].get("inbounds", []), 1):
        inbounds.append({"uuid": inbound_uuid(index), "tag": inbound["tag"]})
    return {
        "uuid": body.get("uuid", PROFILE_UUID),
        "name": body["name"],
        "config": body["config"],
        "inbounds": inbounds,
    }


def has_duplicate_inbound_tag(body):
    profile_uuid = body.get("uuid")
    existing = {
        inbound["tag"]
        for profile in state["profiles"]
        if profile["uuid"] != profile_uuid
        for inbound in profile["inbounds"]
    }
    incoming = {inbound["tag"] for inbound in body["config"].get("inbounds", [])}
    return bool(existing & incoming)


def objects_for_inbounds(uuids):
    known = {
        item["uuid"]: item
        for profile in state["profiles"]
        for item in profile["inbounds"]
    }
    return [known[uuid] for uuid in uuids if uuid in known]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def send_json(self, payload, status=200):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authenticated(self):
        if "panel_auth=ok" in self.headers.get("Cookie", ""):
            return True
        data = b"<html><body>authorization required</body></html>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return False

    def do_GET(self):
        if self.path == "/auth/login?caddy=test-secret":
            self.send_response(302)
            self.send_header("Set-Cookie", "panel_auth=ok; Path=/; HttpOnly")
            self.send_header("Location", "/authorized")
            self.end_headers()
            return
        if self.path == "/authorized":
            self.send_json({"authorized": True})
            return
        if self.path != "/state" and not self.authenticated():
            return
        routes = {
            "/api/config-profiles": {"response": {"total": len(state["profiles"]), "configProfiles": state["profiles"]}},
            "/api/nodes": {"response": state["nodes"]},
            "/api/internal-squads": {"response": {"total": len(state["squads"]), "internalSquads": state["squads"]}},
            "/api/subscription-templates": {"response": {"total": len(state["templates"]), "templates": state["templates"]}},
            "/api/hosts": {"response": state["hosts"]},
            "/state": state,
        }
        if self.path not in routes:
            self.send_json({"message": "not found"}, 404)
            return
        self.send_json(routes[self.path])

    def do_POST(self):
        if not self.authenticated():
            return
        body = self.body()
        if self.path == "/api/config-profiles":
            if has_duplicate_inbound_tag(body):
                self.send_json({"message": "Inbound tags must be unique", "errorCode": "A113"}, 409)
                return
            profile = profile_from(body)
            state["profiles"].append(profile)
            self.send_json({"response": profile}, 201)
            return
        if self.path == "/api/subscription-templates":
            template = {"uuid": TEMPLATE_UUID, **body, "templateJson": None}
            state["templates"].append(template)
            self.send_json({"response": template}, 201)
            return
        if self.path == "/api/hosts":
            number = len(state["hosts"]) + 1
            host = {"uuid": f"66666666-6666-4666-8666-{number:012d}", **body}
            state["hosts"].append(host)
            self.send_json({"response": host}, 201)
            return
        self.send_json({"message": "not found"}, 404)

    def do_PATCH(self):
        if not self.authenticated():
            return
        body = self.body()
        if self.path == "/api/config-profiles":
            if has_duplicate_inbound_tag(body):
                self.send_json({"message": "Inbound tags must be unique", "errorCode": "A113"}, 409)
                return
            profile = profile_from(body)
            state["profiles"] = [profile if item["uuid"] == body["uuid"] else item for item in state["profiles"]]
            self.send_json({"response": profile})
            return
        if self.path == "/api/nodes":
            node = next(item for item in state["nodes"] if item["uuid"] == body["uuid"])
            node.update(body)
            self.send_json({"response": node})
            return
        if self.path == "/api/internal-squads":
            squad = next(item for item in state["squads"] if item["uuid"] == body["uuid"])
            squad["inbounds"] = objects_for_inbounds(body.get("inbounds", []))
            self.send_json({"response": squad})
            return
        if self.path == "/api/subscription-templates":
            template = next(item for item in state["templates"] if item["uuid"] == body["uuid"])
            template.update(body)
            self.send_json({"response": template})
            return
        if self.path == "/api/hosts":
            host = next(item for item in state["hosts"] if item["uuid"] == body["uuid"])
            host.update(body)
            self.send_json({"response": host})
            return
        self.send_json({"message": "not found"}, 404)


HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
