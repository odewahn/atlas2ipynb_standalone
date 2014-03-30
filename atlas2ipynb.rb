require 'nokogiri'
require 'json'
require 'active_support/inflector'



#*************************************************************************************
# Takes a string and turns it into something that can be used as a filename
# handles special chars and internaitonalization isseus, although
# I'm not sure what it will do with CJKV  languages
#*************************************************************************************
def make_filename(s)
   I18n.enforce_available_locales = false
   out = ActiveSupport::Inflector.transliterate(s).downcase
   out.gsub!(/^.*(\\|\/)/,'')
   out.gsub!(/[^0-9A-Za-z]/,"_")
   # now we want to truncate the name at 50 chars, but do it nicely
   # so that the last word is preserved
   out_shortened = []
   chars = 0
   out.split("_").each do |c|
     if (chars +  c.length) < 50
       out_shortened << c
       chars += c.length
     end
   end
   out = out_shortened.join("_")
   # 
   # Now remove any trailing "_"
   #
   while out[-1] == "_"
     out = out[0,out.length-1]
   end
   return out
end


#*************************************************************************************
#  This function  processes the raw HTML sections using nokogiri.  It looks for 
# headers or code; everything else is treated as HTML.  This can be passed to 
# ipynb directly since markdown is a superset of HTML.  Although I'd originally
# planned to convert HTML to markdown, this proved infeasible with all the many
# edge cases in conversion, such has mathml
#*************************************************************************************
def process_section(n, level, out) 
  n.children.each do |c|  
    if c.name == "section"
       # A section is a container only, so we need to recurse down a level to get the content
       process_section(c, level+1, out)      
    else      
      case c.name
        when "h1", "h2", "h3", "h4", "h4", "h5", "h6"
          out << {
             "cell_type" => "heading",
             "level" => level,
             "metadata" => {}, 
             "source" => c.text
           }
        when "pre","code"
          out << {   
             "cell_type" => "code",
             "collapsed" => false,
             "input" => c.text, 
             "language" => c.attributes["data-code-language"] || "python",
             "metadata" => {}, 
             "outputs" => []
           }
        else
          out << {   
             "cell_type" => "markdown",
             "metadata" => {}, 
             "source" => c.to_s
          }
      end
    end  
  end
  return out
end


#*************************************************************************************
# This function takes a file name with HTML content, parses it with nokogiri, does some
# post-processing on the image links, and then calls process_section to convert
# each element to the corrseponding ipynb cell type (markdown, header, or code)
#*************************************************************************************
def html_to_ipynb(fn)
  #
  # Open the file and parse it w/nokogiri
  #
  f = File.open(fn)
  txt = f.read
  f.close
  doc = Nokogiri::HTML(txt, nil, 'utf-8')
  #
  # Pre-process the doc to fix image URLs so that images can be served by the notebook server
  # You do this by prepending "files/" to the image's relative URL, per this question on stackoverflow:
  #   "inserting image into ipython notebook markdown"
  doc.css("figure img").each do |img|
    src = img.attributes["src"].value
    img.attributes["src"].value = src.split("/").unshift("files").join("/")  #prepends "files" to the src
  end
  #
  # Grab the first h1 tag to use as part of the notebooks filename
  #
  chapter_title = doc.css("section h1").first.text
  #
  # combine the cells we just computed with the ipynb header information
  #
  notebook = {
   "metadata" => {
    "name" => chapter_title
   },
   "nbformat" => 3,
   "nbformat_minor"=> 0,
   "worksheets" => [
    {
     "cells" => process_section(doc.css("section").first,1, []),  
     "metadata" => {}
    }
   ]
  }
  return notebook
end


#*************************************************************************************
# process all html files in the directory
#*************************************************************************************
Dir["ch*.html"].each do |fn|
  out = html_to_ipynb(fn)
  # Compute the new filename, which is the original filename 
  # with the ".html" (last 5 chars) replaced with ".ipynb".   
  title_fn = make_filename(out['metadata']['name'])
  ipynb_fn = "#{fn[0,fn.length-5]}_#{title_fn}.ipynb"
  # Create the file
  f = File.open(ipynb_fn, 'w')
  f.write JSON.pretty_generate(out)
  f.close
end

