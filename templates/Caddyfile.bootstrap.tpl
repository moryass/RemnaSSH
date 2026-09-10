{
	admin off
	email {$ACME_EMAIL}
	acme_ca https://acme-v02.api.letsencrypt.org/directory
}

{$NODE_DOMAIN} {
	root * /srv/www
	try_files {path} /index.html
	file_server
}
