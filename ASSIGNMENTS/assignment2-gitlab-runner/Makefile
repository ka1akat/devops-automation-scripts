.PHONY: install register status logs cleanup

install:
	bash install_gitlab_runner.sh

register:
	@if [ -z "$(GROUP_URL)" ]; then echo "Usage: make register GROUP_URL=<group url>" >&2; exit 1; fi
	bash register_gitlab_runner.sh "$(GROUP_URL)"

status:
	systemctl status gitlab-runner --no-pager
	docker ps --filter name=gitlab-runner

logs:
	docker logs --tail 50 gitlab-runner

cleanup:
	bash cleanup.sh