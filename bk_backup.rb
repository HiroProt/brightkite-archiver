#!/usr/bin/env ruby

# Brightkite Archiver - enter your BK username and password below, and run using
#
# ruby bk_backup.rb
#
# It might take a while depending on how much stuff you have. It might not handle error
# conditions too well, but it worked for me (tm) :)

require 'rubygems'
require 'typhoeus'
require 'json'
require 'set'

total_count = 0
offset = 0
last_fetch_count = 0
page = 1
running_count = 0
$fetched_avatars = Set.new

username = 'YOUR_BK_USERNAME'
password = 'YOUR_BK_PASSWORD'

Dir.mkdir("bk_images") rescue puts "bk_images already exists, we'll use that"
Dir.mkdir("bk_avatars") rescue puts "bk_avatars already exists, we'll use that"

posts = []
last_ts = 9999999999

def fetch_avatars(id, url)
  return if $fetched_avatars.include?(id) or FileTest.exists?("bk_avatars/#{id}-tiny.png")
  puts "fetching avatar at URL #{url}"
  resp = Typhoeus::Request.get(url)
  open("bk_avatars/#{id}.png", "wb") { |file|
    file.write(resp.body)
  }
  resp = Typhoeus::Request.get(url.gsub('.png', '-small.png'))
  open("bk_avatars/#{id}-small.png", "wb") { |file|
    file.write(resp.body)
  }
  resp = Typhoeus::Request.get(url.gsub('.png', '-smaller.png'))
  open("bk_avatars/#{id}-smaller.png", "wb") { |file|
    file.write(resp.body)
  }
  resp = Typhoeus::Request.get(url.gsub('.png', '-tiny.png'))
  open("bk_avatars/#{id}-tiny.png", "wb") { |file|
    file.write(resp.body)
  }
  $fetched_avatars << id
end

while (offset == 0 or last_fetch_count > 0) #and offset < 500
  
  last_fetch_count = 0

  resp = Typhoeus::Request.get("http://#{username}:#{password}@brightkite.com/me/objects.json?limit=1000&before_ts=#{last_ts}")
  data = resp.body
  result = JSON.parse(data)

  last_fetch_count = result.size

  result.each do |o|
    
    running_count += 1
    
    puts "got #{o['object_type']}, #{running_count}"
    
    if o['object_type'] == 'photo'
      ext = o['photo'].split('.').reverse().shift();
      ext = ".#{ext}"
      ext = '' unless ext.size > 2 and ext.size < 5
      
      
      unless FileTest.exists?("bk_images/#{o['id']}#{ext}")
        resp = Typhoeus::Request.get(o['photo'])
        open("bk_images/#{o['id']}#{ext}", "wb") { |file|
          file.write(resp.body)
        }
      end
      
      unless FileTest.exists?("bk_images/#{o['id']}-feed#{ext}")
        resp = Typhoeus::Request.get(o['photo'].gsub(/#{ext}$/, "-feed#{ext}"))
        open("bk_images/#{o['id']}-feed#{ext}", "wb") { |file|
          file.write(resp.body)
        }
      end
      
      # update photo URI
      o['photo'] = "bk_images/#{o['id']}#{ext}"
    end
    
    # handle comments
    if o['comments_count'] > 2
      puts "fetching comments for #{o['id']}"
      comments_resp = Typhoeus::Request.get("http://#{username}:#{password}@brightkite.com/objects/#{o['id']}/comments.json?limit=1000")
      comments_result = JSON.parse(comments_resp.body)
      o['comments'] = comments_result
    else
      o['comments'] = []
      o['comments'] << o['first_comment'] if o['first_comment']
      o['comments'] << o['last_comment'] if o['last_comment']
    end
    
    # handle avatars
    puts "handling avatars for #{o['id']}"
    fetch_avatars(o['creator']['id'], o['creator']['avatar_url'])
    o['creator']['avatar_url'] = "bk_avatars/#{o['creator']['id']}.png"
    o['creator']['small_avatar_url'] = nil
    o['creator']['smaller_avatar_url'] = nil
    o['creator']['tiny_avatar_url'] = nil
    o['comments'].each do |c|
      if c['creator']['avatar']
        fetch_avatars(c['creator']['id'], c['creator']['avatar'])
        c['creator']['avatar_url'] = "bk_avatars/#{c['creator']['id']}.png"
        c['creator']['avatar'] = nil
      else
        fetch_avatars(c['creator']['id'], c['creator']['avatar_url'])
        c['creator']['avatar_url'] = "bk_avatars/#{c['creator']['id']}.png"
        c['creator']['small_avatar_url'] = nil
        c['creator']['smaller_avatar_url'] = nil
        c['creator']['tiny_avatar_url'] = nil
      end
    end
    
    posts << o
    last_ts = o['created_at_ts']
    
  end
  
  open("bk_posts_#{page}.json", "wb") { |file|
    file.write(JSON.dump(posts))
  }
  posts = []
  
  total_count += last_fetch_count
  offset = total_count
  
  page += 1
  
end
