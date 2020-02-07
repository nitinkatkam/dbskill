require 'sinatra'
require 'sinatra/config_file'
require 'mongo'
require 'date'
require 'json'
require 'logger'
require 'faker'
# Faker - https://github.com/faker-ruby/faker

config_file 'config.yml'

set :bind, settings.web[:bind]
set :port, settings.web[:port]
#set :server, 'thin'

enable :sessions, :logging

client = Mongo::Client.new(settings.db[:uri])

logger = Logger.new(STDOUT)
# logger = Logger.new('logfile.log')
logger.level = Logger::INFO

get '/' do
    erb :home
end

def get_fake_person()
    addr = Faker::Address
    gender = Faker::Gender.binary_type
    person = {
        '_id' => 'N' + rand(999).to_s.rjust(3, '0'), #This can generate duplicates
        'name' => if gender == 'Male' then Faker::Name.male_first_name + ' ' + Faker::Name.last_name else Faker::Name.female_first_name + ' ' + Faker::Name.last_name end,
        'designation' => Faker::Company.profession.capitalize,
        'company' => Faker::Company.name,
        'city' => addr.city,
        'country' => addr.country,
        'gender' => gender,
        'nationality' => Faker::Nation.nationality,
        'manager' => Faker::Name.name   
    }
end

get '/personnel/new' do
    @person = get_fake_person()
    erb :personnel_edit
end

get '/personnel/edit/:id' do
    @personnel = client['personnel'].find({"_id": params['id']})
    @person = @personnel.first()
    erb :personnel_edit
end

post '/personnel/delete/:id' do
    client['personnel'].delete_one({"_id": params['id']})
    'Deleted'
end

get '/personnel/list' do
    @personnel_list = client['personnel'].find() #.sort({"joined_on": 1})
    @explainer = @personnel_list.explain()
    erb :personnel_list
end

post '/personnel/save' do
    doc = params
    # doc['_id'] = doc['code']
    # if not doc.has_key?('_id') or doc('_id') == nil
        # client['personnel'].insert_one(doc, {writeConcern: 1})
    # else
        client['personnel'].update_one({'_id': doc['_id']}, { '$set' => doc }, {upsert: TRUE, multi: FALSE, writeConcern: 1})
    #     #BSON::ObjectId.from_string(doc_id)
    # end
end


get '/personnel/search' do
    erb :personnel_search
end


get '/personnel/skillmatch' do
    erb :personnel_skillmatch
end


post '/personnel/find' do
    'Size: ' + params['fieldname'].length.to_s
    numFields = params['fieldname'].length
    
    criteria = {}

    for x in 0..(numFields-1) do
        if params['fieldvalue'][x].length > 0
            criteria[params['fieldname'][x]] = params['fieldvalue'][x]
        end
    end

    @personnel_list = client['personnel'].find(criteria) #.sort({"manager": 1})

    sort_criteria = {}
    if params.has_key? 'sortfieldname' #and params['sortfieldname'].length > 0
        params['sortfieldname'].each do |iter|
            if iter.length > 0
                sort_criteria[iter] = 1
            end
        end
        @personnel_list = @personnel_list.sort(sort_criteria)

        logger.debug 'SORTING: ' + sort_criteria.length.to_s
    else
        logger.debug 'NO SORTING'
    end

    @explainer = @personnel_list.explain()
    erb :personnel_list
end
