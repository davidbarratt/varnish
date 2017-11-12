FROM debian:stretch

RUN apt-get update && apt-get install -y \
		varnish \
	--no-install-recommends && rm -r /var/lib/apt/lists/*

COPY ./etc /etc/varnish

CMD [ "varnishd", "-F", "-f", "/etc/varnish/default.vcl", "-s", "file,/tmp,128m" ]
