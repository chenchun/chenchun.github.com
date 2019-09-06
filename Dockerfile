FROM jekyll/jekyll
ADD ./blog /blog
WORKDIR /blog
RUN touch Gemfile.lock && \
	chmod a+w Gemfile.lock && bundle install
CMD mkdir -p _site && chmod 777 _site && bundle exec jekyll serve -H 0.0.0.0
