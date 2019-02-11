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
                option.gsub!(/[^a-z0-9\s]/i, '')
                option.strip!

                anonymous_voters = result[poll_name]['anonymous_voters'] || 0

                poll_record = Poll.where(post_id: @post.id, name: poll_name)

                result[poll_name]["options"].each do |opt|
                  if opt['html'].strip.gsub(/[^a-z0-9\s]/i, '') === option
                    opt['anonymous_votes'] = base
                    anonymous_voters += base
                  end
                end

                result[poll_name]['anonymous_voters'] = anonymous_voters
              end
            end
          end
        end
      end

      result.each do |poll_name, poll_data|
        unless ::Poll.exists?(post_id: @post.id, name: poll_name)
          DiscoursePoll::Poll.create!(@post.id, poll_data)
        end

        poll = ::Poll.where(post_id: @post.id, name: poll_name)

        poll.update_all(anonymous_voters: poll_data['anonymous_voters'])

        ::PollOption.where(poll: poll.first).destroy_all

        poll_data['options'].each do |option|
          ::PollOption.create!(
            poll: poll.first,
            digest: option["id"],
            html: option["html"].strip,
            anonymous_votes: option['anonymous_votes'],
          )
        end
      end

      result
    end
  end

  class DiscoursePoll::PollsValidator
    prepend BaseVotesPollExtension
  end
end
