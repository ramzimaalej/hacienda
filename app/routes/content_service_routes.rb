require 'sinatra/base'
require 'json'
require_relative '../../app/stores/file_data_store'
require_relative '../web/request_error_handler'
require_relative '../exceptions/page_not_found_error'
require_relative '../web/wiring'
require_relative '../../app/github/github'
require_relative '../../app/security/hmac_authorisation'
require_relative '../../app/web/halt'
require_relative '../web/wiring'

module Hacienda

  class HaciendaService < Sinatra::Base
    include Wiring

    ALLOWED_LOCALES_REGEX = '(en|es|pt|cn|de)'

    # These settings should be set to false in order to circumvent Sinatra's default error handling in development
    set :show_exceptions, false
    set :raise_errors, false

    set(:auth) do |authorised|
      condition do
        halt_if.unauthorised(request) if authorised
      end
    end

    def has_accept_language(value)
      (not request.env['HTTP_ACCEPT_LANGUAGE'].nil?) == value
    end

    set(:has_language) do |value|
      condition do
        has_accept_language(value)
      end
    end

    #Status

    get '/status' do
      '{"status":"OK"}'
    end

    #Content Updated

    post '/content-updated' do
      local_content_repo.pull_latest_content
      'content updated'
    end

    #Updating Generic

    put %r{/(.+)/(.+)/#{ALLOWED_LOCALES_REGEX}$}, auth: true do
      type, id, locale = params[:captures]
      sinatra_response(update_content_controller.update(type, id, params[:data], locale, request.env['HTTP_LAST_MODIFIED_BY']))
    end

    #Publishing Generic

    post %r{/(.+)/(.+)/#{ALLOWED_LOCALES_REGEX}$}, auth: true do
      type, id, locale = params[:captures]
      sinatra_response(publish_content_controller.publish(type, id, request.env['HTTP_IF_MATCH'], locale))
    end

    #Create

    post %r{/(.+)/#{ALLOWED_LOCALES_REGEX}$}, auth: true do
      type, locale = params[:captures]
      sinatra_response(create_content_controller.create(type, params[:data], locale, request.env['HTTP_LAST_MODIFIED_BY']))
    end

    #Finding all Generic

    get '/:type/public', has_language: true do
      public_content_store.find_all(params[:type], get_accept_language).to_json
    end

    get '/:type', has_language: true do
      draft_content_store.find_all(params[:type], get_accept_language).to_json
    end

    #Getting Generic

    get '/:type/:id/public', has_language: true do
      public_content_store.find_one(params[:type], params[:id], get_accept_language).to_json
    end

    get '/:type/:id', has_language: true do
      draft_content_store.find_one(params[:type], params[:id], get_accept_language).to_json
    end

    get %r{/(.+)/(.+)/#{ALLOWED_LOCALES_REGEX}$} do
      changes_in_the_past = (-1)*request.env['rack.request.query_hash']['v'].to_i
      draft_content_store.find_locale_resource(params[:type], params[:id], params[:locale], changes_in_the_past)
    end

    #Delete

    delete %r{/(.+)/(.+)/#{ALLOWED_LOCALES_REGEX}$} do
      type, id, locale = params[:captures]
      sinatra_response(delete_content_controller.delete(id, type, locale))
    end

    delete '/:type/:id' do
      sinatra_response(delete_content_controller.delete_all(params[:type], params[:id]))
    end

    #Errors

    error do
      error_handler.handle(raised_error)
    end

    error 404 do
      error_handler.handle(Errors::PageNotFoundError.new('/'))
    end

    def raised_error
      request.env['sinatra.error']
    end

    def get_accept_language
      accepted_values = ['en','es','pt','de']
      passed_locale = request.env['HTTP_ACCEPT_LANGUAGE']
      accepted_values.include?(passed_locale) ? passed_locale : 'en'
    end

    def sinatra_response(service_http_response)
      service_http_response.apply_to_sinatra_response(self.response)
      service_http_response.body
    end


  end

end
