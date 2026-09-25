# Every route the app answers, mounted engines included, as plain data.
#
# The authorization matrix and the Playwright route crawl both start from this
# list rather than from one they keep by hand. A route added to
# config/routes.rb then fails both until someone decides who may reach it and
# whether a browser can load it. Before this, coverage was whichever paths a
# test author remembered, and a new page was covered by nothing.
module RouteInventory
  Route = Data.define(:verb, :path, :controller, :action) do
    # "GET /recipes/:id" - the key both the matrix and the crawl use.
    def key
      "#{verb} #{path}"
    end
  end

  module_function

  def all(routes = Rails.application.routes, prefix: "")
    routes.routes.flat_map do |route|
      spec = prefix + route.path.spec.to_s

      if (engine = mounted_engine(route))
        all(engine.routes, prefix: spec)
      else
        path = spec.delete_suffix("(.:format)")
        path = "/" if path.empty?
        verbs = route.verb.presence&.split("|") || [ "ANY" ]
        verbs.map do |verb|
          Route.new(verb: verb, path: path, controller: route.defaults[:controller], action: route.defaults[:action])
        end
      end
    end.uniq(&:key)
  end

  def mounted_engine(route)
    app = route.app
    app = app.app if app.is_a?(ActionDispatch::Routing::Mapper::Constraints)
    app if app.is_a?(Class) && app < Rails::Engine
  end
end
