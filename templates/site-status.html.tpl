<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="description" content="Northgate service availability and incident history.">
  <title>Northgate Status</title>
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <style>
    :root{color-scheme:light;--ink:#273240;--green:#168557;--green-bg:#eaf7f1;--line:#dde2e8;--muted:#6d7885;--page:#f7f8fa}
    *{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:15px/1.5 Arial,Helvetica,sans-serif}a{color:#2865b7}.wrap{width:min(850px,calc(100% - 36px));margin:auto}header{background:#fff;border-bottom:1px solid var(--line)}.header{height:68px;display:flex;align-items:center;justify-content:space-between}.brand{font-weight:800;font-size:1.05rem;color:var(--ink);text-decoration:none}.brand span{font-weight:400;color:var(--muted)}
    main{padding:48px 0 70px}.summary{display:flex;align-items:center;gap:12px;margin-bottom:24px;padding:20px 22px;border:1px solid #bfe5d4;border-radius:7px;background:var(--green-bg);color:#116641;font-size:1.05rem;font-weight:700}.dot{width:12px;height:12px;border-radius:50%;background:var(--green)}
    .updated{margin:-12px 2px 28px;color:var(--muted);font-size:.78rem}.group{margin-bottom:24px;border:1px solid var(--line);border-radius:7px;background:#fff;overflow:hidden}.group h2{margin:0;padding:16px 20px;border-bottom:1px solid var(--line);font-size:.9rem}.component{display:grid;grid-template-columns:1fr 130px 100px;gap:20px;align-items:center;padding:15px 20px;border-bottom:1px solid var(--line)}.component:last-child{border-bottom:0}.bars{display:flex;gap:3px}.bars i{height:22px;flex:1;border-radius:2px;background:#55b789}.state{text-align:right;color:var(--green);font-size:.82rem;font-weight:700}
    h1{margin:42px 0 16px;font-size:1.4rem}.incident{margin-bottom:14px;padding:18px 20px;border:1px solid var(--line);border-radius:7px;background:#fff}.incident-head{display:flex;justify-content:space-between;gap:20px}.incident h2{margin:0;font-size:.95rem}.incident time{color:var(--muted);font-size:.78rem}.incident p{margin:9px 0 0;color:var(--muted);font-size:.88rem}.subscribe{display:flex;justify-content:space-between;gap:20px;align-items:center;margin-top:36px;padding:22px;border:1px solid var(--line);border-radius:7px;background:#fff}.subscribe b{display:block}.subscribe span{color:var(--muted);font-size:.86rem}.button{padding:10px 15px;border-radius:5px;background:#2865b7;color:#fff;text-decoration:none;font-weight:700;font-size:.84rem}
    footer{padding:25px 0;border-top:1px solid var(--line);color:var(--muted);font-size:.8rem}.footer{display:flex;justify-content:space-between}
    @media(max-width:620px){main{padding-top:30px}.component{grid-template-columns:1fr 75px}.bars{display:none}.incident-head,.subscribe,.footer{display:block}.incident time,.subscribe .button{display:inline-block;margin-top:12px}.footer span{display:block;margin-top:5px}}
  </style>
</head>
<body>
  <header><div class="wrap header"><a class="brand" href="/">Northgate <span>service status</span></a><a href="mailto:support@__DOMAIN__">Contact support</a></div></header>
  <main class="wrap"><div class="summary"><span class="dot"></span><span>All systems operational</span></div><div class="updated">Service checks are updated automatically throughout the day.</div>
    <section class="group"><h2>Core services</h2><div class="component"><span>Public website</span><div class="bars"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span class="state">Operational</span></div><div class="component"><span>Application services</span><div class="bars"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span class="state">Operational</span></div><div class="component"><span>Account access</span><div class="bars"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span class="state">Operational</span></div></section>
    <section class="group"><h2>Supporting systems</h2><div class="component"><span>Email delivery</span><div class="bars"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span class="state">Operational</span></div><div class="component"><span>Documentation</span><div class="bars"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span class="state">Operational</span></div></section>
    <h1>Recent notices</h1><article class="incident"><div class="incident-head"><h2>Scheduled database maintenance completed</h2><time>Completed</time></div><p>Routine maintenance was completed within the planned window. No further action is required.</p></article><article class="incident"><div class="incident-head"><h2>No incidents reported</h2><time>Previous 30 days</time></div><p>All monitored services remained within normal operating parameters.</p></article>
    <div class="subscribe"><div><b>Need help with your account?</b><span>Service-specific questions are handled by the support team.</span></div><a class="button" href="mailto:support@__DOMAIN__">Email support</a></div>
  </main>
  <footer><div class="wrap footer"><span>Northgate Status</span><span>__DOMAIN__ · Availability history</span></div></footer>
</body>
</html>
