sed 's,MODULE_VERSION,0.1.3,g' META.json.in > META.json
git commit -a -m 'preparation for v0.1.3' 
git tag -s v0.1.3
git archive --format=tar --prefix=openbarter-0.1.3/ v0.1.3 | gzip -9 > ../openbarter-0.1.3.tar.gz
# git archive --format zip --prefix=openbarter-0.1.3/ v0.1.3 --output ../openbarter-0.1.3.zip
cp doc/doc-ob.pdf ../openbarter-doc-0.1.3.pdf
git log --no-merges v0.1.3 ^release_0.1.2 > ../ChangeLog-0.1.3
git shortlog --no-merges v0.1.3 ^release_0.1.2 > ../ShortLog-0.1.3
git diff --stat --summary -M release_0.1.2 v0.1.3 > ../diffstat-0.1.3
