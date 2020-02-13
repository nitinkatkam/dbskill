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

# logger = Logger.new(STDOUT)
logger = Logger.new('logfile.log')
logger.level = Logger::INFO

##
# Handles the root route
# TODO
get '/' do
    @events = get_todays_events(client)
    @explainer = @events.explain()
    erb :home
end

##
# Gets the events for today
def get_todays_events(client)
    @events = client['personnel'].aggregate([ 
        {'$project' => {'name' => '$name', 'events' => {'$objectToArray' => {'birthday' => '$birthdate', 'hiredate' => '$hiredate', 'anniversary' => '$anniversarydate'}}}}, 
        {'$unwind' => '$events'}, 
        {'$match' => {'events.v' => {'$ne' => ''}}},
        {'$project' => {'name' => '$name', 'type' => '$events.k', 'date' => {'$dateFromString' => {'dateString' => '$events.v'}}}},
        {'$addFields' => { 'date_this_year' => { '$dateFromParts' => {'year' => Date.today.year, 'month' => {'$month' => '$date'}, 'day' => {'$dayOfMonth' => '$date'}} } }},
        {
            '$match' => 
            {
                '$expr' => {'$eq' => [
                    '$date_this_year',
                    {'$dateFromParts' => {'year' => Date.today.year, 'month' => Date.today.month, 'day' => Date.today.day}}
                ]}
            }            
        }
    ])
    # {'$project' => {'name' => '$name', 'type' => '$events.k', 'date' => '$events.v', 'date_this_year' => {'$dateFromParts' => {'year' => Date.today.year, 'month' => {'$month' => '$events.v'}, 'day' => {'$dayOfMonth' => '$events.v'}} }}}, 
end

##
# Old code for the home page - TO REVIEW OR DELETE
def old_home_method(client)    
    #TODO: Set the find criteria to birthdate $lte Date.today + 7 and birthdate $gte Date.today - 1
    @bdays = client['personnel'].find({"birthdate" => {'$exists' => TRUE} }).sort({'birthdate' => 1}).to_a

    @upcoming = []
    @notupcoming = []
    @bdays.each { |bday|        
        iter_date = bday['birthdate'] #Gives a Time object, not a Date object
        if iter_date == nil then next end

        begin
            iter_date = Date.parse(iter_date.to_s)
            age = ((Date.today - iter_date).to_i/365).floor
            
            next_bday_date = iter_date.next_year(age)
            if next_bday_date < Date.today then next_bday_date = iter_date.next_year(age+1) end

            # logger.info "Checking #{next_bday_date}"
            
            if next_bday_date - Date.today < 7
                bday['next_bday_date'] = next_bday_date
                @upcoming.append(bday)
            end
        rescue
            nil
        end
    }
    @upcoming.sort! { |a,b| a['next_bday_date'] <=> b['next_bday_date'] }

    erb :home
end

##
# Returns a map with details for a fake person
#
# @return [Hash]
#
# @example get_fake_person() 
#   #=> { '_id' => 'N073', 'name' => 'Nitin Reddy', 'designation' => 'Software Developer', 'company' => 'Unbricker Corporation', 'city' => 'Dubai', 'country' => 'UAE', 'gender' => 'Male', 'nationality' => 'Indian', 'manager' => 'Reddy' }
#
def get_fake_person()
    # departments = ['IT', 'Sales', 'Marketing', 'HR', 'Administration', 'Field Service', 'Engineering', 'Professional Services', 'Customer Service', 'Maintenance', 'Technical Support', 'Research and Development', 'Accounting', 'Finance', 'Purchasing', 'Production']
    addr = Faker::Address
    gender = Faker::Gender.binary_type
    person = {
        '_id' => 'N' + rand(999).to_s.rjust(3, '0'), #This can generate duplicates
        'name' => if gender == 'Male' then Faker::Name.male_first_name + ' ' + Faker::Name.last_name else Faker::Name.female_first_name + ' ' + Faker::Name.last_name end,
        'designation' => Faker::Company.profession.capitalize,
        # 'dept' => departments[(rand * (departments.length-1)).to_i],  # Commented out as this usually doesn't correspond to the Faker's professions
        'company' => Faker::Company.name,
        'city' => addr.city,
        'country' => addr.country,
        'gender' => gender,
        'nationality' => Faker::Nation.nationality,
        'manager' => Faker::Name.name   
    }
end

##
# Displays the form for creating new personnel
get '/personnel/new' do
    if settings.hacks['preload_new_personnel'] == 'true'
        @person = get_fake_person()
    end
    erb :personnel_edit
end

##
# Displays the form for editing personnel
get '/personnel/edit/:id' do
    @personnel = client['personnel'].find({"_id": params['id']})
    @person = @personnel.first()
    if @person['skills'] != nil
        skilarr = @person['skills']
        @person['skills'] = skilarr.join ', '
    end
    @explainer = @personnel.explain()
    erb :personnel_edit
end

##
# Deletes a person
post '/personnel/delete/:id' do
    client['personnel'].delete_one({"_id": params['id']})

    redirect '/personnel/list'
end

##
# Removes the profile pic for a person
post '/personnel/unsetpic/:id' do
    client['personnel'].update_one(
        {'_id': params['id']}, 
        { 
            '$unset' => {
                'profilepic': ''
            } 
        }, 
        {multi: FALSE, writeConcern: 1}
    )

    redirect '/personnel/list'
end

##
# Displays the list of personnel
get '/personnel/list' do
    @personnel_list = client['personnel'].find() #.sort({"joined_on": 1})
    @explainer = @personnel_list.explain()
    erb :personnel_list
end

##
# Saves the personnel record
post '/personnel/save' do
    doc = params
    
    logger.info params['profilepic']

    if params['profilepic']
        filename = params['profilepic']['filename']
        tempfile = params['profilepic']['tempfile']
        target = '/files/profilepic_' + doc['_id'] + File.extname(filename) #"public/files/#{filename}"
      
        File.open('public'+target, 'wb') {|f| f.write tempfile.read }
    
        doc['profilepic'] = target #Target is given to browsers in img src
        doc['profilepic_filename'] = filename  #Keep original filename
    end

    skillarr = []
    for iterskill in doc['skills'].split(',')
        skillarr.append iterskill.lstrip.rstrip
    end
    doc['skills'] = skillarr

    # if not doc.has_key?('_id') or doc('_id') == nil
        # client['personnel'].insert_one(doc, {writeConcern: 1})
    # else
        client['personnel'].update_one({'_id': doc['_id']}, { '$set' => doc }, {upsert: TRUE, multi: FALSE, writeConcern: 1})
    #     #BSON::ObjectId.from_string(doc_id)
    # end

    redirect '/personnel/list'
end

##
# Displays the personnel search form
get '/personnel/search' do
    erb :personnel_search
end

##
# Displays the skill search form
get '/personnel/skillmatch' do
    erb :personnel_skillmatch
end

##
# Displays the skill search results
post '/personnel/skillmatch' do
    @keyword = params['skills']    
    @personnel_list = client['personnel'].find(
        {'skills' => params['skills']}, 
        {'collation' => { "locale" => "en_US", 'strength' => 2 }}
    ) #TODO: Create an index for this collation
    @explainer = @personnel_list.explain()
    erb :personnel_skillmatch
end

##
# Displays the personnel search results
post '/personnel/find' do
    # 'Size: ' + params['fieldname'].length.to_s
    numFields = params['fieldname'].length
    
    criteria = {}

    for x in 0..(numFields-1) do
        if params['fieldvalue'][x].length > 0
            if settings.search['matchType'] == 'regex' then
                criteria[params['fieldname'][x]] = /#{Regexp.escape( params['fieldvalue'][x] )}/i
            else
                criteria[params['fieldname'][x]] = params['fieldvalue'][x]
            end
        end
    end

    @personnel_list = client['personnel'].find(
        criteria, 
        'collation' => { "locale" => "en_US", 'strength' => 2 }
    ) #.sort({"manager": 1})

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


get '/attendance/checkin' do
    erb :attendance_checkin
end

post '/attendance/checkin' do
    # TODO: Validation
    # TODO: personnel_id should come from the login
    # ['personnel_id', 'timein', 'timeout', 'location_name']
    client['attendance_checkin'].insert_one params
    # erb :attendance_checkin
    redirect '/'
end

get '/attendance/review' do
    @checkindata = client['attendance_checkin'].find()
    @explainer = @checkindata.explain()
    erb :attendance_review
end
