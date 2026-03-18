install:
	shards install

update:
	shards update

format:
	crystal tool format --check src spec

lint:
	ameba src spec

test:
	crystal spec

clean:
	rm -rf .crystal-cache temp
