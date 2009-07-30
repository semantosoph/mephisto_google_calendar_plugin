require 'digest/md5'

module MephistoGravatarPlugin

  def get_gravatar(email, size = 80)
    default = 'identicon' # gravatar.com offers three default avatars: identicon, monsterid and wavatar
    rating = 'pg' # gravatar.com accepts the following values as rating: g (nicest), pg, r, x (baddest)

    # gravatar.comneeds a MD5 hash of the email address to find the correct image
    mail_hash = Digest::MD5.hexdigest(email)

    image_tag("http://www.gravatar.com/avatar/#{mail_hash}?size=#{size}&rating=#{rating}&default=#{default}", :alt => "Gravatar image", :class => "gravatar")
  end

end
