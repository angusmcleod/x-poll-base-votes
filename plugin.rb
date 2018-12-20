# name: x-poll-base-votes
# about: Base votes poll extension
# version: 0.9
# authors: Angus McLeod
# url: https://github.com/angusmcleod/x-poll-base-votes

register_asset 'stylesheets/common/x-poll-base-votes.scss'
register_asset 'stylesheets/mobile/x-poll-base-votes.scss', :mobile

after_initialize do
  module BaseVotesPollExtension
    def validate_polls
      result = super

      return result if !result

      raw_polls = @post.raw.split("[/poll]")
      post_votes = @post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD]

      raw_polls.each do |raw_poll|
        poll_name = nil
        config_line = nil

        catch :not_regular_poll do
          raw_poll.each_line do |line|
            next if line.empty?

            if line.include?('[poll')
              config_line = line
              poll_name = config_line[/name=(\w+)/m, 1] if config_line.include?('name=')
            end

            if comment = line[/<!--(.*?)-->/m, 1]
              comment.strip!

              if base = comment.partition('base=').last.to_i
                ## Validations only apply if there is an attempt to add base votes.
                ## This allows other comments / options.

                ## Name is essential for the base votes feature
                if !poll_name
                  @post.errors.add(:base, I18n.t("poll.base_votes_requires_name"))
                  return result
                end

                ## Go to next poll if this is not a regular poll
                #throw :not_regular_poll unless config_line && config_line.include?('type=regular')

                option = line.partition('<!--').first.strip
                option.gsub!(/[*-]/,'')
                option.strip!

                voters = result[poll_name]['voters'] || 0
                anonymous_voters = result[poll_name]['anonymous_voters'] || 0

                result[poll_name]["options"].each do |opt|
                  if opt['html'].strip.gsub(/[^a-z0-9\s]/i, '') === option.gsub(/[^a-z0-9\s]/i, '')
                    option_votes = 0
                    option_voters = 0

                    if post_votes.present?
                      post_votes.each do |_, v|
                        next unless poll_votes = v[poll_name]

                        poll_votes.each do |option_id|
                          if option_id === opt['id']
                            option_votes += 1
                            option_voters += 1
                          end
                        end
                      end
                    end

                    opt["votes"] = option_votes + base
                    opt['anonymous_votes'] = base
                    voters += option_voters + base
                    anonymous_voters += base
                  end
                end

                result[poll_name]['voters'] = voters
                result[poll_name]['anonymous_voters'] = anonymous_voters
              end
            end
          end
        end
      end

      @post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD] = result

      result
    end
  end

  class DiscoursePoll::PollsValidator
    prepend BaseVotesPollExtension
  end
end
