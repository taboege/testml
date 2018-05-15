all: yaml-test-suite
	mkdir -p yaml
	cp yaml-test-suite/test/*.tml yaml/
	perl -e 'print "$$_\n" for map {s!^yaml/(.*)\.tml$$!$$1!;$$_} grep /\.tml$$/, @ARGV' yaml/* > yaml/list

test:
	(sleep 0.5; open http://localhost:12345/) &
	static -p 12345

yaml-test-suite:
	git clone -b testml-new git@github.com:yaml/$@

clean:
	rm -fr yaml-test-suite
