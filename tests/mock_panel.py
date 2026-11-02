#!/usr/bin/env python3

import json
from http.server import BaseHTTPRequestHandler, HTTPServer


PROFILE_UUID = "11111111-1111-4111-8111-111111111111"
NODE_UUID = "22222222-2222-4222-8222-222222222222"
SQUAD_UUID = "33333333-3333-4333-8333-333333333333"
TEMPLATE_UUID = "44444444-4444-4444-8444-444444444444"

state = {
    "profiles": [],
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

    def do_GET(self):
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
        body = self.body()
        if self.path == "/api/config-profiles":
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
        body = self.body()
        if self.path == "/api/config-profiles":
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
