## The MIT License (MIT)
##
## Copyright (c) 2014-2024
## Savin Max <mafei.198@gmail.com>
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.

class String
  def is_number?
    true if Float(self) rescue false
  end
end

desc "Generate configs Sql format file from Excel"
task :generate_config => :environment do
  config_dir = File.expand_path("#{FRAMEWORK_ROOT_DIR}/app/config_data/gameconfig")
  sheets = []

  table_map = {}
  Dir.foreach(config_dir) do |config_file_path|
    next if config_file_path =~ /~\$.+\.xls/
    extname = File.extname(config_file_path)
    if extname == '.xlsx'
      s = Roo::Excelx.new(File.expand_path(config_dir + '/' + config_file_path))
    elsif extname == '.xls'
      s = Roo::Excel.new(File.expand_path(config_dir + '/'+ config_file_path))
    else
      next
    end

    sql = ""

    s.sheets.each do |sheet|
      next if sheet !~ /^config_.+/
      sheets << sheet
    end

    s.sheets.each do |sheet|
      next if sheet !~ /^config_.+/
      s.default_sheet = sheet
      table_name = sheet.pluralize
      table_map[table_name] = {field_names: [], rows: []}
      field_names = []
      field_indexes = {}
      s.row(2).each_with_index do |field, index|
        begin
          next if field.blank?
          name, type = field.split(":")
          field_indexes[index] = type
          table_map[table_name][:field_names] << name
          unless ['string', 'text', 'integer', 'int', 'float', 'boolean', 'integer-array', 'float-array', 'origin'].include?(type)
            raise "TYPE ERROR: #{type} didn't defined."
          end
        rescue => e
          puts "In sheet: #{sheet}, field: #{field}"
          raise e
        end
      end
      4.upto(s.last_row).map do |row|
        row_values = []
        s.row(row).each_with_index do |value, index|
          next if field_indexes[index].nil?
          if value == 'NULL'
            value = 'undefined' if value == 'NULL'
          else
            field_type = field_indexes[index]
            if field_type == 'integer' or field_type == 'int'
              if value.blank?
                value = 0 
              else
                value = value.to_i
              end
            elsif field_type == 'integer-array' or field_type == 'int-array' or field_type == 'float-array'
              if value.nil?
                value = "[]"
              else
                value = "[#{value.gsub(";", ",")}]"
              end
            elsif field_type == 'float'
              value = 0.0 if field_type == 'float' and value.blank?
            elsif field_type == 'string' or field_type == 'text'
              value_class = value.class
              if value_class == Fixnum or value_class == Float
                value = value.to_i.to_s
              end
              value = "<<\"#{value}\">>"
            end
          end
          row_values << value
        end
        table_map[table_name][:rows] << row_values
      end
    end

  end

  File.open("#{FRAMEWORK_ROOT_DIR}/game_server/include/config_data_names.hrl", 'w') do |io|
    io.puts "%%% Generated by generate_config.rake \n"
    io.puts "-define(CONFIG_DATA_NAMES, [\n"
    table_names = table_map.map{|table_name, v| table_name}
    io.puts %Q{    #{table_names.join(",\n    ")}}
    io.puts "])."
  end

  File.open("#{FRAMEWORK_ROOT_DIR}/game_server/include/config_data_records.hrl", 'w') do |io|
    io.puts "%%% Generated by generate_config.rake \n"
    content = ""
    table_map.each do |table_name, data|
      content << "-record(#{table_name}, {\n"
      size = data[:field_names].size
      data[:field_names].each_with_index do |field, index|
        content << "        #{field}"
        content << ",\n" if index < size - 1
      end
      content << "}).\n\n"
    end
    io.puts content
  end

  `mkdir -p #{FRAMEWORK_ROOT_DIR}/app/generates`
  File.open("#{FRAMEWORK_ROOT_DIR}/app/generates/config_data.erl", 'w') do |io|
    io.puts "%%% Generated by generate_config.rake \n"
    content = []
    table_map.each do |table_name, data|
      rows = data[:rows].map do |row_values|
        "{#{row_values.first}, {#{table_name}, #{row_values.join(', ')}}}"
      end

      content << "{#{table_name}, [#{rows.join(', ')}]}"
    end
    io.puts %Q{
-module(config_data).
-export([find/2, all/1, first/1, last/1, next_key/2]).

-define(MAP, [#{content.join(",")}]).

get_tuple(Table) ->
    case lists:keyfind(Table, 1, ?MAP) of
        false -> [];
        {Table, Value} -> Value
    end.

find(Table, Key) ->
    case lists:keyfind(Key, 1, get_tuple(Table)) of
        false -> undefined;
        {Key, Value} -> Value
    end.

first(Table) ->
    case get_tuple(Table) of
        [] -> undefined;
        TupleList -> 
            {_Key, Value} = hd(TupleList),
            Value
    end.

last(Table) ->
    case get_tuple(Table) of
        [] -> undefined;
        TupleList -> 
            {_Key, Value} = lists:nth(length(TupleList), TupleList),
            Value
    end.

all(Table) ->
    R = lists:foldl(fun({_Id, Record}, Result) ->
        [Record|Result]
    end, [], get_tuple(Table)),
    lists:reverse(R).

next_key(Table, Key) ->
    TupleList = get_tuple(Table),
    Length = length(TupleList),
    next_key(TupleList, 1, Length, Key).

next_key(_, Index, Length, _) when Index > Length -> undefined;
next_key(TupleList, Index, Length, Key) ->
    {CurrentKey, _} = lists:nth(Index, TupleList),
    if
        CurrentKey =:= Key ->
            if
                Index < Length ->
                    {NextKey, _} = lists:nth(Index + 1, TupleList),
                    NextKey;
                true ->
                    undefined
            end;
        true ->
            next_key(TupleList, Index + 1, Length, Key)
    end.
    }
  end
end
