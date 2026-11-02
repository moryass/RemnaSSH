<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="description" content="Helio platform documentation and implementation guides.">
  <title>Helio Documentation</title>
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <style>
    :root{color-scheme:light;--ink:#1c2533;--blue:#3568d4;--pale:#f5f7fa;--line:#dfe4eb;--muted:#697586;--code:#202a3b}
    *{box-sizing:border-box}body{margin:0;color:var(--ink);font:15px/1.6 Arial,Helvetica,sans-serif}a{color:inherit;text-decoration:none}header{position:sticky;top:0;z-index:2;border-bottom:1px solid var(--line);background:#ffffffed;backdrop-filter:blur(8px)}
    .header{height:64px;display:flex;align-items:center;gap:35px;width:min(1240px,calc(100% - 36px));margin:auto}.brand{font-weight:800;font-size:1.05rem}.brand span{color:var(--blue)}.search{flex:1;max-width:480px;padding:10px 13px;border:1px solid var(--line);border-radius:6px;background:var(--pale);color:var(--muted)}.header nav{margin-left:auto;display:flex;gap:23px;font-size:.86rem}
    .layout{display:grid;grid-template-columns:230px minmax(0,760px) 190px;gap:48px;width:min(1240px,calc(100% - 36px));margin:auto}.sidebar,.toc{position:sticky;top:64px;align-self:start;height:calc(100vh - 64px);padding-top:34px}.sidebar{border-right:1px solid var(--line)}.side-title{margin:20px 0 8px;color:var(--muted);font-size:.69rem;font-weight:800;letter-spacing:.09em;text-transform:uppercase}.sidebar a{display:block;padding:6px 0}.sidebar a.active{color:var(--blue);font-weight:700}
    article{padding:58px 0 90px}h1{margin:0 0 15px;font-size:2.45rem;line-height:1.15;letter-spacing:-.03em}.intro{margin:0 0 31px;color:var(--muted);font-size:1.08rem}h2{margin:42px 0 12px;padding-top:5px;font-size:1.45rem}p{margin:0 0 16px}.note{margin:25px 0;padding:16px 18px;border-left:4px solid var(--blue);background:#eef4ff}.note b{display:block;margin-bottom:3px}.steps{padding-left:20px}.steps li{padding:5px 0 9px 5px}
    pre{overflow:auto;margin:20px 0;padding:19px;border-radius:7px;background:var(--code);color:#e7edf8;font:13px/1.6 Consolas,Monaco,monospace}code{font-family:Consolas,Monaco,monospace}.toc{font-size:.8rem}.toc b{display:block;margin-bottom:10px}.toc a{display:block;padding:5px 0;color:var(--muted)}.updated{margin-top:55px;padding-top:20px;border-top:1px solid var(--line);color:var(--muted);font-size:.8rem}
    @media(max-width:950px){.layout{grid-template-columns:210px minmax(0,1fr)}.toc{display:none}}@media(max-width:680px){.header nav{display:none}.layout{display:block}.sidebar{display:none}article{padding-top:40px}.search{max-width:none}h1{font-size:2rem}}
  </style>
</head>
<body>
  <header><div class="header"><a class="brand" href="/">Helio<span>Docs</span></a><div class="search">Search documentation…</div><nav><a href="#setup">Guides</a><a href="#workspace">API reference</a><a href="mailto:support@__DOMAIN__">Support</a></nav></div></header>
  <div class="layout"><aside class="sidebar"><div class="side-title">Getting started</div><a class="active" href="#overview">Overview</a><a href="#setup">Initial setup</a><a href="#workspace">Workspace settings</a><div class="side-title">Platform</div><a href="#access">Access control</a><a href="#monitoring">Event delivery</a><a href="#monitoring">Monitoring</a><div class="side-title">Resources</div><a href="#workspace">API reference</a><a href="mailto:support@__DOMAIN__">Contact support</a></aside>
    <article id="overview"><h1>Platform overview</h1><p class="intro">Helio provides a consistent way to connect services, manage access and observe routine operations from one workspace.</p><div class="note"><b>Before you begin</b>Ask a workspace administrator to create your account and confirm which environment you should use.</div><h2 id="setup">Initial setup</h2><p>A new workspace starts with a single administrator and no connected services. Complete these steps before inviting the wider team.</p><ol class="steps"><li>Choose a workspace name and default region.</li><li>Create separate credentials for development and production.</li><li>Configure an event destination and send a test event.</li><li>Invite team members with the minimum access they need.</li></ol><h2 id="workspace">Workspace settings</h2><p>Settings apply to every project in a workspace. Changes to credentials and event destinations are recorded in the activity log.</p><pre><code>GET /v1/workspaces/current
Authorization: Bearer &lt;workspace-token&gt;
Accept: application/json</code></pre><h2 id="access">Access control</h2><p>Use roles to separate administration, deployment and read-only access. Service credentials should be created for one purpose and rotated regularly.</p><h2 id="monitoring">Monitoring</h2><p>The activity view records configuration changes and delivery attempts. For automated checks, request the health endpoint at a conservative interval.</p><div class="updated">Documentation home: __DOMAIN__ · Maintained by the Helio platform team</div></article>
    <aside class="toc"><b>On this page</b><a href="#overview">Overview</a><a href="#setup">Initial setup</a><a href="#workspace">Workspace settings</a><a href="#access">Access control</a><a href="#monitoring">Monitoring</a></aside>
  </div>
</body>
</html>
