require 'nokogiri'
require 'reverse_markdown'
require 'json'


#
# List of HTML elements that we'll convert; note that handling
# for most common elements will is taken care of by the 
# reverse_markdown gem.  (Note that even though <ol> and <ul> are
# supported in markdown, they are not handled correctly by reverse_markdown)
#
TARGETS = {
  "markdown" => ["p"],
  "header"   => ["h1", "h2", "h3", "h4", "h4", "h5", "h6"],
  "code" => ["pre", "code"],
  "html_passthrough" => ["iframe","video", "table", "figure", "ul", "ol"]
}

# Return a header cell
def ipynb_header_cell(line)
  return {
     "cell_type" => "heading",
     "level" => line[:level],
     "metadata" => {}, 
     "source" => ReverseMarkdown.parse(line[:text_val])
   }
end

# return a markdown cell
def ipynb_markdown_cell(line)
  return {   
     "cell_type" => "markdown",
     "metadata" => {}, 
     "source" => ReverseMarkdown.parse(line[:raw_val])
  }
end

# return a code cell
def ipynb_code_cell(line)
  return {   
     "cell_type" => "code",
     "collapsed" => false,
     "input" => line[:text_val], 
     "language" => line[:attributes]["data-code-language"] || "python",
     "metadata" => {}, 
     "outputs" => []
   }
end

# return html pass-through cell for markup that is not supported in 
# "true" markdown or correctly handled by the reverse_html gem
def ipynb_html_passthrough_cell(line)
  return {   
     "cell_type" => "markdown",
     "metadata" => {}, 
     "source" => line[:raw_val]
   }
end



#*************************************************************************************
#  This function  processes the raw HTML sections from nokogiri and 
#  converts each element to simplified JSON data structure that will be 
#  post-processed into ipynb cells
#*************************************************************************************
def process_section(n, level, out)
  
  n.children.each do |c|  
    TARGETS.each do |type,tags|
      if tags.include? c.name
         out << { 
           :type => type, 
           :raw_val => c.to_s, 
           :text_val => c.text, 
           :level => level,
           :attributes => c.attributes }
           break
      end
    end      
    # reverse_markdown is going to do most of the tree walking for us, but we do
    # need to recurse for <section> tags
    if c.name == "section" 
      process_section(c, level+1, out)      
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
  doc = Nokogiri::HTML(txt)
  #
  # Pre-process the doc to fix image URLs so that images can be served by the notebook server
  # You do this by prepending "files/" to the image's relative URL, per this question on stackoverflow:
  #   "inserting image into ipython notebook markdown"
  doc.css("figure img").each do |img|
    src = img.attributes["src"].value
    img.attributes["src"].value = src.split("/").unshift("files").join("/")  #prepends "files" to the src
  end
  #
  # post-processing is done, so now pass in the first section to process_section
  #
  raw_json = process_section(doc.css("section").first,1, [])
  #
  # process each returned element into it's closest ipython notebook equivalent
  #
  cells = []
  raw_json.each do |line|
    case line[:type]
       when "header"
          cells << ipynb_header_cell(line)
       when "markdown"
          cells << ipynb_markdown_cell(line)
       when "code"
          cells << ipynb_code_cell(line)
       when "html_passthrough"
          cells << ipynb_html_passthrough_cell(line)
    end
  end
  #
  # combine the cells we just computed with the ipynb header information
  #
  notebook = {
   "metadata" => {
    "name" => ""
   },
   "nbformat" => 3,
   "nbformat_minor"=> 0,
   "worksheets" => [
    {
     "cells" => cells,  
     "metadata" => {}
    }
   ]
  }
  
  return notebook
  
end


#
# process all html files in the directory
Dir["ch*.html"].each do |fn|
  # Compute the new filename, which is the original filename 
  # with the ".html" (last 5 chars) replaced with ".ipynb".   
  ipynb_fn = "#{fn[0,fn.length-5]}.ipynb"
  # Create the file
  out = html_to_ipynb(fn)
  f = File.open(ipynb_fn, 'w')
  f.write JSON.pretty_generate(out)
  f.close
end
