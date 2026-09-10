{
	admin off
	https_port {$CADDY_INTERNAL_PORT}
	auto_https disable_redirects

	servers 127.0.0.1:{$CADDY_INTERNAL_PORT} {
		protocols h1 h2
		timeouts {
			read_header 10s
			idle 10m
		}
	}
}

http://{$NODE_DOMAIN} {
	redir https://{$NODE_DOMAIN}{uri} permanent
}

https://{$NODE_DOMAIN} {
	bind 127.0.0.1
	tls {
		issuer acme {
			email {$ACME_EMAIL}
			dir https://acme-v02.api.letsencrypt.org/directory
		}
	}
	encode zstd gzip

	header {
		Content-Security-Policy "default-src 'self'; object-src 'none'; frame-ancestors 'none'"
		Referrer-Policy "same-origin"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "DENY"
	}

	@xhttp path {$XHTTP_PATH}*
	handle @xhttp {
		reverse_proxy unix//dev/shm/remnassh-xhttp.sock {
			flush_interval -1
			transport http {
				versions h2c
			}
		}
	}

	handle {
		root * /srv/www
		try_files {path} /index.html
		file_server
	}
}
