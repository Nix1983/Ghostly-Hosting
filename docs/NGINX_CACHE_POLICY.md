# Nginx cache policy

Newly generated configurations forward an application's `Cache-Control` unchanged.
When it is missing or empty, Nginx adds `no-store`, including on error responses.
The location-level directive stays in place to preserve security-header inheritance.

This change does not modify existing server configurations automatically.

Run `bash test/nginx_cache_tests.sh` on Linux with Python 3 and Nginx installed.
Tests use an isolated Nginx instance and loopback ports, without reloading the system service.
