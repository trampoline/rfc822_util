require 'action_mailer'
require 'tmail'
require 'base64'

module Rfc822Util
  class << self
    def logger=(l)
      @logger=l
    end

    def logger
      @logger ||= Logger.new($stderr)
    end
  end

  module_function

  # extract the first message/rfc822 attachment from the RFC822 encoded content, and return it as a TMail::Mail
  # if +strip_content+ is true then message content will be discarded, and only headers processed
  def extract_journalled_mail(mail, strip_content=true)
    journal_mail = TMail::Mail.parse(mail) if mail.is_a?(String)
    
    # get the attachment
    attachment = journal_mail.parts.select{ |p| p.content_disposition == "attachment" || p.content_type == "message/rfc822" }.first
    
    # complain if the email has no attachment to extract
    raise "attempted to extract journalled mail, but message has no attachments: \n#{mail}\n\n" unless attachment

    mail_content = strip_content ? discard_mail_body(attachment.body) : attachment.body

    TMail::Mail.parse(mail_content)
  end

  # discard everything after the first \n\n , i.e. all message body content from an RFC822 encoded mail
  def discard_mail_body(content)
    content.gsub(/^(.*?)\r\n\r\n.*$/m, '\1')
  end

  # remove angle brackets from a header string
  def strip_header(header)
    header.gsub(/^<(.*)>$/, '\1')
  end

  def with_headers(headers)
    [*(headers||[])].map{|h| yield h}
  end

  # remove angle brackets from one or more headers
  def strip_headers(headers)
    with_headers(headers){|h| strip_header(h)}
  end

  # parse an address to a hash
  def parse_address(address)
    address = TMail::Address.parse(address) if address.is_a?(String)
    {:name=>address.name, :email_address=>address.address}
  end

  # parse one or more addresses to hash. failures result in a warning logged
  def parse_addresses(addresses)
    [*(addresses||[])].map do |a| 
      begin
        parse_address(a)
      rescue Exception=>e
        logger.warn("failure parsing: #{a}")
        logger.warn(e)
        nil
      end
    end.compact
  end

  # turn a TMail::Mail into a hash suitable for JSON representation
  # if strip_content is true then neither subject nor body will be present
  def mail_to_hash(mail, strip_content=true)
    mail = TMail::Mail.parse(mail) if mail.is_a?(String)

    message_id = strip_header(mail.message_id) if mail.message_id
    sent_at = mail.date.xmlschema
    in_reply_to = strip_headers(mail.in_reply_to).first if mail.in_reply_to
    references = strip_headers(mail.references) if mail.references
    from = parse_addresses(mail.from_addrs).first
    sender = parse_addresses(mail.sender).first
    to = parse_addresses(mail.to_addrs)
    cc=parse_addresses(mail.cc_addrs)
    bcc=parse_addresses(mail.bcc_addrs)

    h = {
      :message_id=>message_id,
      :sent_at=>sent_at,
      :in_reply_to=>in_reply_to,
      :references=>references,
      :from=>from,
      :sender=>sender,
      :to=>to,
      :cc=>cc,
      :bcc=>bcc
    }

    if !strip_content
      h[:subject] = mail.subject
    end

    h
  end
end
