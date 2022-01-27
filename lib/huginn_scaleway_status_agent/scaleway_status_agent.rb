module Agents
  class ScalewayStatusAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_5m'

    description do
      <<-MD
      The huginn Scaleway status agent checks the Scaleway service status.

      `debug` is used to verbose mode.

      `changes_only` is only used to emit event about a currency's change.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "status": {
              "indicator": "none",
              "description": "All Systems Operational"
            }
          }
    MD

    def default_options
      {
        'debug' => 'false',
        'expected_receive_period_in_days' => '2',
        'changes_only' => 'true'
      }
    end

    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :debug, type: :boolean

    def validate_options

      if options.has_key?('changes_only') && boolify(options['changes_only']).nil?
        errors.add(:base, "if provided, changes_only must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def check
      check_status
    end

    private

    def check_status()

      uri = URI.parse("https://status.scaleway.com/api/v2/status.json")
      request = Net::HTTP::Get.new(uri)
      request["Authority"] = "status.scaleway.com"
      request["Accept"] = "*/*"
      request["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36"
      request["X-Requested-With"] = "XMLHttpRequest"
      request["Sec-Gpc"] = "1"
      request["Sec-Fetch-Site"] = "same-origin"
      request["Sec-Fetch-Mode"] = "cors"
      request["Sec-Fetch-Dest"] = "empty"
      request["Referer"] = "https://status.scaleway.com/"
      request["Accept-Language"] = "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7"
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end


      if interpolated['debug'] == 'true'
        log "response.body"
        log response.body
      end

      log "fetch status request status : #{response.code}"
      parsed_json = JSON.parse(response.body)
      payload = { :status => { :indicator => "#{parsed_json['status']['indicator']}", :description => "#{parsed_json['status']['description']}" } }

      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          memory['last_status'] = payload.to_s
          create_event payload: payload
        else
          if interpolated['debug'] == 'true'
            log "no diff"
          end
        end
      else
        create_event payload: payload
        if payload.to_s != memory['last_status']
          memory['last_status'] = payload.to_s
        end
      end
    end
  end
end
